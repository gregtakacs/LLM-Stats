# H3w step 2: move the hub UI to the root of its origin, then 308 `/hub…`, serve two hostnames in the browser stack

## Goal

With step 1's role gate live and both layouts served, finish the move the shipped UI was
waiting for: the hub's static files, service worker and manifest go to the **root** of the
hub origin (`/app.js`, `/sw.js`, `/manifest.webmanifest`, `/index.html`, `/api/…`), every
in-page reference becomes root-relative, the Chat iframe and the project/session deep
links build their OpenCode URL from the **paired host** returned by the API (via
`/h/<host>/oc` on the hub origin), and only then does `/hub` and `/hub/…` answer **308** to
the same path with the prefix removed (query preserved) and the dual `/hub` serving is
dropped. The browser test stack (step 5's harness) is widened here to serve a hub hostname
and its paired OpenCode hostname over one Chrome instance, with a fake OpenCode upstream,
because step 3 and 5 both need it and it is cheapest to prove the move in the same stack
that will judge it.

Binds: `docs/h3-design.md` §3 (root layout, the 308, `/h/<host>/oc`), §7 (UI moves),
§10.3 (`/sw.js` on the hub is the hub's own worker; on the OpenCode role it is relayed —
done step 1), §5's same-origin `/h/<host>/oc` for the picker. `verify-ui.md` applies.

## Read first

- `docs/h3-design.md` §3, §7, §10.3, §10.4 (root-relative), and the §8 step-0 note on the
  picker using same-origin `/h/<host>/oc`.
- `docs/specs/h3w-design.md` §4 (screenshots), §5 (the two-hostname stack you build here).
- `docs/specs/h3w-1-roles-routing.md` §3 — the routing/framing seams you now consume.
- `hub/static/index.html`, `app.js`, `api.js`, `data.js`, `renew.js`, `state.js`,
  `manifest.webmanifest`, `sw.js`, and `views/sessions.js`, `views/chat.js`,
  `views/projects.js`, `views/history.js` — every `/hub/…` string and every place a URL is
  built.
- `hub/api.py` — how static/manifest/worker are served and `NO_STORE_NAMES`; `csp_for`.
- `hub/proxy.py` after step 1 — the `/h/<host>/oc` route and role table.
- `hub/tests/test_ui.py`, `test_h2c_browser.py`, `test_h2_browser.py` (`BrowserStack`
  ~line 270, `launch_chrome` ~367, `PageSession` ~400).
- `~/.config/opencode/rules/verify-ui.md` — grow, don't one-shot; the four screenshot modes.

## Contract

### Files

Modify: everything under `hub/static/` that references a path or builds an OpenCode URL
(`index.html`, `app.js`, `api.js`, `data.js`, `renew.js`, `views/*.js`,
`manifest.webmanifest`, `sw.js`), `hub/api.py` (serve at root, drop dual `/hub` serving,
add the 308, add the paired host to `/api/hosts`), and `hub/tests/test_ui.py`,
`test_h2_browser.py` (the two-hostname stack), `test_h2c_browser.py`, `test_sessions_ui.py`
expectations, plus `hub/tests/test_routing.py` (the 308 rows). Do not change gate/config/
proxy role logic beyond wiring the 308 and `/api/hosts`; do not touch `install.sh`,
`doctor.py`, or the OpenCode-origin renewal (step 3).

### Static move (`hub/static`, `hub/api.py`)

- Every absolute `/hub/<x>` reference becomes `/<x>`: `index.html`'s manifest/icon/
  stylesheet/module-script `src`, `app.js`/`data.js`/`views/*` fetches, `sw.js` cache keys
  and its own scope, `manifest.webmanifest`'s `start_url`, `scope`, and icon `src`. The
  never-cache set (`NO_STORE_NAMES`) covers the new root names.
- The service worker registers at `/sw.js` with scope `/` on the hub origin (step 1 already
  routes it; here it is the hub's real worker, not the h1 replacement body).
- The hub's API fetches move from `/hub/api/…` to `/api/…`; `redirect:"manual"` handling
  unchanged (a 308 now never appears for the UI's own paths).
- The Chat iframe (`views/chat.js`) and any OpenCode deep link build
  `https://<paired-opencode-host>/…`, where `<paired-opencode-host>` comes from the API,
  never hard-coded (R-H3-3). On the hub origin, the session picker / OpenCode fetches that
  must stay same-origin go through `/h/<host>/oc/…`.
- `/api/hosts` (and any endpoint the UI reads for host metadata) now includes, per hub
  host, its paired `opencode` host or `null`, sourced from config (step 1's `HubConfig`).

### The 308 (`hub/api.py` / `hub/proxy.py`)

- On the hub role, `GET|HEAD /hub` and `/hub/<rest>` → **308**, `Location` = `/<rest>`
  (empty rest → `/`), query string preserved exactly, no body, `Cache-Control` as the other
  redirects. Drop the dual `/hub` static/API serving that step 1 kept. Other methods on
  `/hub…` are already gate-capped; a POST to `/hub/api/…` 308s the same way (a redirect a
  manual-fetch caller sees as `opaqueredirect`, which is fine now that the UI no longer
  uses `/hub`).

### Browser stack: two hostnames (`hub/tests/test_h2_browser.py`)

- `BrowserStack` serves **two** hostnames on one hub port: a hub host and a paired opencode
  host, launched with `--host-resolver-rules=MAP <hub>,<opencode> 127.0.0.1` and
  `sites=[{hub,opencode}]`. Add a **fake OpenCode** upstream the stack owns (it already
  fakes the verifier) so on the opencode host `/`, `/sw.js` and `/api/session` answer,
  letting the relay and the with-hub path be compared. `PageSession` gains the second
  origin's cookie scope. Existing single-host tests must keep passing (default to the hub
  host).

## Acceptance

`python3 tools/run_tests.py hub.tests.test_ui hub.tests.test_routing
hub.tests.test_h2_browser hub.tests.test_h2c_browser` each matching
`^ok +hub[.]tests[.]<module> .* OK$`, then the scope guard. Screenshots per `verify-ui.md`:
the hub UI at **390×800** and **1440×900**, **light and dark**, over the two-hostname
stack, **every PNG read** and stored under `$DELEGATE_EVIDENCE_DIR`; the Chat iframe visibly
loads from the paired origin.

## Out of scope

Renewal on the OpenCode origin (step 3), installer/doctor/docs (step 4), the full
with/without-hub acceptance matrix and direct-OpenCode control (step 5). Keep `/hub`→308
only for the hub role.

## Notes

Do the file move and the 308 in this order within the step (files first, then flip
`/hub` to 308, then update `test_routing`'s expectations) so no intermediate state breaks
the running UI; the suite only has to be green at the end of the step.
