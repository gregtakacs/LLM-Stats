# H3 step 3: the UI at the root of the hub origin, Chat on the paired OpenCode origin

`"hard": false`. Design step 2 (`docs/h3-design.md` §3, §7). Paths only: **no new look**. Do not
change `hub/static/app.css`, colours, sizes, layout or copy beyond what is listed here. After
step 2 the server routes the new URL space, and the three browser modules fail until this step
moves the UI and gives the browser test stack two HTTPS hostnames. At the end of this step every
module of both suites passes, the browser ones included, with no skips.

## Read first

- `docs/h3-design.md` §3, §5, §7; `docs/h1-design.md` §7.1 (the iframe URL formats), §8.3 (PWA,
  service worker rules); `~/.config/opencode/rules/verify-ui.md` (binding for screenshots).
- `hub/static/` all of it, in particular `index.html`, `manifest.webmanifest`, `sw.js`, `app.js`
  (service worker registration, sign-in button, `reloadChat`), `data.js`, `renew.js`,
  `views/chat.js`, `views/sessions.js` (`apiBase`, `chatServerUrl`, `chatSrcFor`, `serverKey`),
  `views/projects.js` (host rows, `oc_url`).
- `hub/routes.py` (the table: what each path does on each role) and `hub/api.py`
  (`/api/hosts` rows: `opencode_origin`, `oc_url`).
- `hub/tests/test_h2_browser.py` (`DevTools`, `BrowserStack`, `PageSession`, `launch_chrome`),
  `hub/tests/test_sessions_ui.py` (`OriginDevTools`, `watch_origin`, the fake OpenCode),
  `hub/tests/test_h2c_browser.py`, `hub/tests/test_ui.py`.
- `docs/specs/h3-3-front-spike.py`: a working probe of the HTTPS front below. Read it; build the
  real one from it.

## Contract: the UI

1. Every `/hub/` path in `hub/static/` becomes root-relative: `/app.js`, `/app.css`,
   `/manifest.webmanifest`, `/icons/…`, `/api/me`, `/api/hosts`, `/renew.html`, and the sign-in
   button's `window.location.assign("/")`. No string `/hub` remains anywhere in `hub/static/`
   (comments included).
2. `manifest.webmanifest`: `start_url` `/`, `scope` `/`, icons `/icons/icon-192.png`,
   `/icons/icon-512.png`, `/icons/icon-maskable-512.png` (files stay where they are; the server
   serves `hub/static/` at the root).
3. `sw.js`: registered as `navigator.serviceWorker.register("/sw.js", { scope: "/" })`.
   `SHELL_CACHE = "{project}-shell-v4"` (old caches drop on activate, as now); `SHELL` is `/`,
   `/index.html`, `/app.css`, `/app.js`, `/state.js`. The fetch handler: non-GET → return;
   another origin → return; then, **before any cache use**, return (network, never cached) for
   `/api/…` (`pathname === "/api"` or starts with `/api/`), `/h/…` (`/h` or `/h/`), `/renew.html`,
   and `/hub` or `/hub/…`; every other same-origin GET is network-first exactly as today (the
   only `cache.put`, gated on status 200 and `type === "basic"`); the navigation fallback is
   `/index.html`. Rewrite the file's comments for the new layout (OpenCode lives on another origin
   now; this worker's scope is the whole hub origin).
4. **Chat origin.** The page learns the paired OpenCode origin from `/api/hosts`: the
   `opencode_origin` of the rows (all rows carry the same value). It is used only if it is a string
   matching `^https://[a-z0-9.-]+$`; anything else counts as unpaired. Never derive it from
   `location`. Export a pure helper `chatOrigin(hosts)` from `views/chat.js` returning the
   validated origin or `null`.
5. **Chat iframe `src`** (absolute URLs now): no session chosen → `<origin>/`; a session →
   `<origin>/server/<serverKey(server)>/session/<id>` where `server` is `<origin>` for the root
   host and the row's `oc_url` for any other host (its `oc_url` is used only when it equals
   `<origin> + "/h/" + name + "/oc"`, `name` matching the existing `HOST_NAME`). `chatSrcFor`
   and `chatServerUrl` take the origin from `chatOrigin`, never `window.location.origin`.
   `reloadChat` keeps its `renewed=` cache-buster on the absolute URL. Before `/api/hosts` has
   answered, the iframe has no `src`.
6. **Unpaired** (`chatOrigin` is `null`): the iframe gets no `src` and is hidden; a new
   `<p id="chat-notice" class="empty-note" hidden>` (in `index.html`, inside `#view-chat`,
   before the iframe) shows `No OpenCode address is paired with this hub address.`; choosing a
   project does not open the session picker. Paired: the notice is hidden.
7. **Picker** API base: `/h/<name>/oc` for **every** host, the root host included
   (`/h/<root>/oc/api/session?…`, `POST /h/<root>/oc/api/session`); `name` validated with
   `HOST_NAME`, else no base (as today). Same-origin, so nothing else in the picker changes.
8. Projects host rows: unchanged logic; the copied/visible URL is the row's `oc_url` (now on the
   OpenCode origin). The root row still shows no URL.
9. `serverKey` test vector (generic now):
   `serverKey("https://code.example.com") === "aHR0cHM6Ly9jb2RlLmV4YW1wbGUuY29t"` and
   `serverKey("https://code.example.com/h/beta/oc") === "aHR0cHM6Ly9jb2RlLmV4YW1wbGUuY29tL2gvYmV0YS9vYw"`.

## Contract: the browser test stack (two hostnames over HTTPS)

- New module `hub/tests/browser_front.py` with `FrontDevTools(DevTools)`: one **reader thread**
  owns the socket's reads; command replies are handed to the waiting `cmd()` caller by id (lock +
  condition), every other event is queued for `events()`, and each `Fetch.requestPaused` is
  answered from the reader thread with a fire-and-forget `Fetch.continueRequest` (no nested wait
  on that thread, ever). Sends take a lock. `Fetch.enable` with
  `[{"urlPattern": "https://*", "requestStage": "Request"}]` before the first navigation.
- **Routing**: `front.routes: dict[hostname, port]`. A paused `https://<h>/<rest>` with `h` in
  `routes` continues with `url = f"http://{h}:{port}/{rest}"` and the request's own headers, any
  `Cookie` removed, plus `Cookie: <front.jar[h]>` when the jar has an entry for `h`. Anything else
  → `Fetch.failRequest` with `errorReason: "BlockedByClient"`. The Origin is the browser's own
  (no swapping): `OriginDevTools` and `watch_origin` in `test_sessions_ui.py` are deleted and
  their users switched to the front.
- **Cookies**: `front.jar: dict[hostname, str]` stands in for the provider's cookie (a per-host
  jar models both layouts: one entry per host, or the same value for both = a parent-domain
  cookie). `PageSession.set_cookie()` puts `idp_session=<value>` in the jar for both hostnames by
  default; `set_cookie(hosts=[...])` for a subset.
- `BrowserStack`: `HUB = "hub.example.com"`, `OC = "code.example.com"`; config
  `"sites": [{"hub": HUB, "opencode": OC}]`; `base_url = "https://hub.example.com"`; Chrome's
  `--host-resolver-rules` maps both names to `127.0.0.1`; the front routes both to the hub's port.
  `BrowserStack(..., opencode_upstream=URL)` (used by `test_sessions_ui`'s fake OpenCode) as
  today. Keep `HOST` only if something still needs it; nothing may use `http://` page URLs.
- A cross-origin iframe's URL is read with `Page.getFrameTree` (child frame `url`), never through
  `contentWindow`. The fake OpenCode's request log (Host `code.example.com`) proves what the
  iframe asked for.
- The service worker is not exercised in the browser (its script fetch may not be paused by
  `Fetch`); its contract is tested statically. A failed registration must not fail a test.

## Tests (required; then look beyond this list for the neighbouring cases)

- **Static** (`test_ui.py`): no `/hub` anywhere in `hub/static/`; the manifest values; `sw.js`
  never-cache list (all four entries) appears before the first `caches.`/`cache.` use; cache name
  `{project}-shell-v4`; the `SHELL` list; the registration call with `scope: "/"`; `chatOrigin`
  accepts `https://code.example.com` and refuses `http://code.example.com`,
  `https://code.example.com/`, `https://code.example.com:8443`, `javascript:alert(1)`, `""`,
  `null`, a number, `https://CODE.example.com`; the two `serverKey` vectors; no `location.origin`
  in `views/sessions.js` or `views/chat.js`; `app.css` unchanged from step 2
  (`git diff --quiet delegate/h3-2-routing -- hub/static/app.css` in a test is not needed: the
  chain's verify checks it).
- **Browser** (update the three modules to the front; their scenarios keep their meaning): the
  page's `location.origin` is `https://hub.example.com`; Projects/History cold loads as before;
  the renewal scenarios count `/renew.html` lines in the hub's access log; the picker lists and
  creates sessions through `/h/alpha/oc/api/session` (the fake OpenCode sees `/api/session`; the
  hub log line is `oc alpha`); choosing a session gives the child frame the URL
  `https://code.example.com/server/aHR0cHM6Ly9jb2RlLmV4YW1wbGUuY29t/session/<id>` and the fake
  OpenCode receives that path on Host `code.example.com`; a non-root host's session uses the
  `…/h/beta/oc` key; the default chat frame is `https://code.example.com/`; the POST carries
  `Origin: https://hub.example.com` (the hub accepted it: prove it from the fake's log). New:
  an unpaired stack (`sites: [{"hub": HUB}]`) shows the notice, no iframe `src`, and selecting a
  project opens no picker; a stack whose page is asked on `https://code.example.com/` gets
  OpenCode (the fake), not the hub's shell.
- **Bypass check**: a test asserting that the page's own JavaScript never requests
  `https://code.example.com/api/…` or `…/h/…/api/…` (the front records every paused URL): the
  hub page reaches OpenCode's API only through its own origin.

## Screenshots (binding, `verify-ui.md`)

1440×900 and 390×800, light and dark: the populated hub at `https://hub.example.com/` with the
Chat pane showing the fake OpenCode page in the iframe; the picker open; the unpaired notice.
Read every PNG and say in the report what each shows. Compare with the look before this step: it
must be the same apart from what the iframe contains.

## Verify

While working: `python3 tools/run_tests.py hub.tests.test_ui hub.tests.test_h2_browser
hub.tests.test_h2c_browser hub.tests.test_sessions_ui`. Once at the end: `python3
tools/run_tests.py` (both suites). The harness re-runs both suites and requires `test_ui` and the
three browser modules to report `OK` with no skips.

## Out of scope

Any server change (`hub/*.py`); the OpenCode-origin renewal and the "Sign in to OpenCode" notice
(step 4); `app.css`; new copy beyond the notice text above; installer, doctor and docs.
