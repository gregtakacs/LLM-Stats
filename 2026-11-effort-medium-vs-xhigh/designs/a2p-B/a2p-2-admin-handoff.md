# A2P step 2 — the admin session: hand-off link, live row, Stop, and every disabled state

Status: ready. Chain: `a2p-chain.json` step `a2p-2-admin-handoff`. **Hard step**: it builds URLs
and renders server strings. Verify = the step's modules + scope guard while working; its final
`verify` runs the full gate. Read first: `docs/specs/a2p-design.md` §3–§6, `docs/specs/a2a-design.md`
§4 (protocol shapes) and §7 (the picker's whole contract), `docs/specs/a2a-9-admin-page.md` (what
consumes the hand-off), `docs/specs/a2-design.md` ruling 26, and step 1's spec (the bar, the seam).
Code: `hub/static/views/adminsession.js` (the seam you fill in), `hub/static/views/sessions.js`,
`hub/static/views/claude.js` (the two-click pattern you copy), `hub/static/views/running.js` (the
poll you ride — never duplicate), `hub/tests/test_c1a1_browser.py` (`_world_answer`: the scripted
launcher this step copies), `hub/tests/test_sessions_ui.py` (stack + CDP helpers).

## Goal

With the data A2a step 6 will send, the dropdown owns a **Project admin** section — the live
row's state, deadline and Stop, or the one reason the hand-off is not offered — and **New admin
session** performs a top-level hand-off to the admin page. Without that data (this base, and any
deployment whose launcher is down), the control degrades to exactly step 1's shape: disabled with
the pinned reason. Nothing here starts or extends a session.

## Files owned

- `hub/static/views/adminsession.js` — the module, completed:
  - `export function adminOrigin(state)` — the selected project's site's admin origin: the
    `admin_origin` of the project's host row in `state.hosts` (the same field `renderAdminLink`
    reads; a project's host is `state.selected.host`, and with one host the root row), or null.
  - `export function adminHandoffUrl(origin, project)` — the one URL builder, §Contract-2.
  - `export function adminState(state, projectName)` — the first `sessions[]` entry in
    `state.launcher` with `target === "admin" && project === projectName`, or null.
  - `export function disabledReason(state, project)` — the pinned string, precedence
    **origin → project_admin → brokered** (design §3): no or unusable origin → `DISABLED_NO_ORIGIN`;
    `options.project_admin !== true` → `DISABLED_OFF`; project's name not in `options.admin_projects`
    (array of strings; missing field = not brokered) → `DISABLED_UNBROKERED`; else null.
  - `export function renderAdminRow(project, state)` — the `.session-row.picker-admin-row` for
    the live session (null when there is none): state word span (`Starting…` / `Running` /
    `Waiting for you` / `Stopped unexpectedly`; an unknown state renders `String(entry.state)` —
    text, never a guess), deadline span (`until HH:MM` from `deadline` **epoch seconds**, local
    24-h, the `running.js` `fmtDeadline` pattern; `No time limit` when `timed === false`; nothing
    when no live deadline), the `rc_name` span when `link` is set, and a real
    `<button type="button" class="claude-btn admin-stop">` Stop/`Really stop?` two-click with the
    4000 ms revert, copied from `claude.js`'s `askStop` (its own timer; two-click state is
    module-local like `dev.confirming`).
  - `export function renderAdminSection(state, project)` — the dropdown's section: head
    `Project admin`, then the live row and/or the reason note, then the `Status unavailable` note
    when `state.launcher === null` (Stop stays visible when a session was known — the point of the
    control is releasing a stuck session and the launcher answers a stop regardless of status);
    returns null only when there is no admin site for the project's host at all — that deployment
    gets no section.
  - `export function paintBar(state)` — drives `#a2p-admin-new`: reason null →
    `aria-disabled="false"`, `title` removed, and `#a2p-admin-link` gets
    `link.href = adminHandoffUrl(origin, project)` + `link.hidden = false`; reason non-null →
    `aria-disabled="true"`, `title` = reason, `link.removeAttribute("href")`, `link.hidden = true`.
    Called from `sessions.js`'s render (it owns the signature; `paintBar`'s output — reason, state
    word, deadline minute, status-null flag — goes into it).
  - `export function handleAdminClick(state)` — reason null → the hand-off: set
    `#a2p-admin-link.href` (already correct from the last paint, re-validated here) and
    `#a2p-admin-link.click()`; never `fetch`, `XMLHttpRequest`, `POST` or an iframe. Reason
    non-null → `sessionsView.open()` (open the dropdown so the reason is *seen*, the only
    behaviour ruling 24's "opens the picker" sentence can mean given the hand-off never happens
    in-panel — recorded under DECISIONS; it is also how touch reaches the reason, which `title`
    cannot deliver).
  - Clicking a live row's Stop → `POST /api/launcher/stop` with body
    `{"target": "admin", "project": <name>}` (hub origin, no step-up — a2a §4; the one row shape
    this module ever sends, and it is `JSON.stringify` of a literal object). 200/ok → refresh the
    answer (`running.refresh()`); 409 → **no stale error**: refresh and let the new row speak (a2a
    §7); other failures → one-line `.claude-error`-family note with our own words
    (`The launcher is not reachable on this host.` on network failure; the response's `detail`
    string as text when the answer carries one, mirroring `running.js`), and `role="alert"`.
  - Opening the dropdown triggers one immediate `running.refresh()` (the `claude.js` pattern:
    `import("./running.js").then(r => r.refresh())`) so a just-opened panel never shows a stale
    deadline; the 10 s cadence stays `running.js`'s, and `tickClocks` keeps re-polling at a passed
    deadline. No second timer here.
  - No import cycle: `sessions.js` imports `adminsession.js` and calls
    `paintBar(state, { openDropdown })` / `handleAdminClick(state, { openDropdown })`, passing the
    opener in; `adminsession.js` imports nothing from `sessions.js`.
- `hub/static/views/sessions.js` — call `renderAdminSection` from `paint` (after the Claude
  section, before the OpenCode head), feed its output into the repaint signature, call `paintBar`
  from the bar paint, pass the opener to `handleAdminClick` from the delegated click route step 1
  installed, and trigger the one refresh-on-open inside `open()`.
- `hub/static/app.css` — `.picker-admin-row`, `.picker-admin-state`, `.picker-note.is-reason`,
  `.admin-stop` (all from existing tokens; the narrow-width rules join the 640 px block).
- Tests: new `hub/tests/test_a2p_admin_browser.py` (the states below; script the launcher with the
  `C1A1BrowserStack._world_answer` pattern — `action == "status"` answers
  `{"ok": true, "sessions": world, "options": {...}}` with `project_admin`/`admin_projects`/
  `admin_members` set per test, and the project's host row carries `admin_origin` through the
  stack's `write_config(hub=...)` `sites` entry — read the stack before faking; the hub relays
  `/api/launcher/status` verbatim, so the a2a step-6 fields are fakeable today without touching
  the hub); `hub/tests/test_ui.py` (fence grows only as §Contract-6 says: the `href` rule becomes
  *the one guarded assignment* — see 4.3); `hub/tests/test_sessions_ui.py` (untouched unless a
  hostile assertion lands better beside its siblings — justify in the commit message).

## Contract

1. **Never** a fetch, POST, XHR, beacon, form or iframe toward the admin origin. The only wire
   write this module makes is `POST /api/launcher/stop` **on the hub origin**.
2. `adminHandoffUrl(origin, project)` returns a string only when *all* hold, else `null`:
   parseable by `new URL()` (a throw is a refusal); `u.protocol === "https:"`;
   `u.pathname === "" || u.pathname === "/"`; `u.search === ""`; `u.hash === ""`;
   `u.username === "" && u.password === ""`; `u.origin !== "null"`. The result is exactly
   `u.origin + "/?project=" + encodeURIComponent(project)` — no `agent`, no trailing path, no
   second parameter. A non-string `project` returns null, never `String(project)`-coerced into
   someone's URL. Unit-pinned table (in the browser module, same pure function):
   `https://admin.example.com` ✓; `https://admin.example.com/` ✓ →
   `https://admin.example.com/?project=a%20b`; `http://admin.example.com` ✗;
   `https://admin.example.com/door` ✗; `https://admin.example.com/?x=1` ✗; `…#f` ✗;
   `https://u:p@admin.example.com` ✗; `admin.example.com` (scheme-less) ✗; `""` ✗; `null` ✗;
   `javascript:...` ✗; a 10 000-char project ✓ with the whole name encoded (no cap in the UI).
3. The hand-off is a real anchor: `link.rel = "noopener"` in the markup (step 1 shipped it),
   `link.href` assigned only from `adminHandoffUrl`'s result, `link.hidden` paired with the
   href's presence, and a href that stops validating gets `removeAttribute("href")` before the
   next paint. `test_ui.py`'s fence pins: `href` is still forbidden via `setAttribute` and there
   is exactly one `\.href = ` assignment in `adminsession.js`, its right-hand side the guarded
   call.
4. Reasons and precedence exactly as the module docs say (origin first, then project_admin, then
   brokered) with the three pinned strings; an absent launcher option is *false*, never true.
5. The Stop body is the literal `{ target: "admin", project: <validated selected project's name> }`
   — the project name comes from the store's own validated row, never from the DOM or the URL.
6. Two-click Stop: first click flips the label to `Really stop?`, 4000 ms of inactivity reverts
   it, the second click posts once (no double-submit while a stop is in flight — mirror
   `dev.busy`/`local.confirming` handling).

## Tests this step must add (each one a state from the task's list; all in
`test_a2p_admin_browser.py`, free ports, `skipIf` per repo convention — the *hard gate* runs
where chromium exists)

| Test | Fixture | Asserts |
|---|---|---|
| hand-off URL | project_admin on, `r1` brokered, origin `https://admin.example.com` | `prop("#a2p-admin-link","href") === "https://admin.example.com/?project=r1"`; `aria-disabled="false"`; `title` absent |
| encoding | a project literally named `Auth — sprint &beta/1` (add it through the stack's repo names) | href ends `?project=Auth%20%E2%80%94%20sprint%20%26beta%2F1`; no raw space or `&` survives |
| navigation only | same, click | the module's CDP pattern records exactly one request to `https://admin.example.com/*`, method GET, request type Document, then `Fetch.failRequest` (the page must not leave the hub origin; `page_errors()` clean; **zero** POSTs toward the admin origin in the recorded set) |
| no admin origin | hub.json with no `admin` site entry (the base config) | `aria-disabled="true"`, title = `Needs the admin origin: A1 phase 2`, no href, click opens the dropdown and the section's reason note shows the same sentence |
| malformed origin | host row `admin_origin` = `http://admin.example.com` | same refusal copy, no href |
| project_admin off | options without the field / false | title = `Project admin is off: enable project_admin in admin.json` |
| not in broker.json | project_admin on, `admin_projects: ["r2"]`, select `r1` | title = `Not in broker.json`; `r2` shows no reason |
| running admin session | sessions row `{target:"admin", project:"r1", state:"running", deadline: <now+60m epoch s>, timed: true, rc_name:"hub/r1", link:"https://claude.example/rc", member:"beta"}` | dropdown shows `Project admin`, `Running`, `until HH:MM` (the pinned minute), the Stop button; `member` is rendered as text if shown at all |
| Stop posts and refreshes | same + a stop answer `{ok:true,result:"stopped"}` and a follow-up status with the row gone | two clicks; the launcher's received doc is `{"action":"stop","target":"admin","project":"r1"}`; the row repaints to no-row; `page_errors()` clean |
| Stop 409 | stop answers `{"ok":false,"error":"already_stopping"}` (a2a §4 code list) then a status without the row | no error text shown; row gone after the refresh |
| status unavailable | launcher unreachable (FakeLauncher answers garbage or the socket closed) after a running row was painted | `Status unavailable` text; Stop control still present and clickable |
| hostile strings | a session `rc_name` `<img src=x onerror=alert(1)>`, member name `‮ses_evil`, a 10 000-char OpenCode title; plus a brokered project named `<script>`-ish text | `#session-picker` `textContent` contains the raw hostile text; DOM has exactly 0 `img`/`script` elements inside the picker; `window.onerror` never fired (add a hook that sets a flag); the hand-off href untouched; the row ellipsizes (scrollWidth of the title span > clientWidth) |
| no sessions | project_admin on, brokered, origin ok, sessions empty | the section shows its head and no row; the empty OpenCode list shows `No sessions yet`; the bar admin control is enabled (a start is exactly what it is for) |
| closed on switch | a running row painted | selecting another project closes the dropdown (the 6eed48f test's assertion, re-run here because the admin row is new paint) |

## Acceptance criteria

1. Verify — exactly the chain's step-2 command (hard: the full gate in one run, every module
   accounted for, plus the hand-off shape guards and the scope guard):

```
set -o pipefail; V="${DELEGATE_EVIDENCE_DIR:-/tmp}/verify-a2p2.log"; python3 tools/run_tests.py > "$V" 2>&1 || { F=$(grep -E '^FAIL +' "$V" | awk '{print $2}' | tr '\n' ' '); [ -n "$F" ] || { tail -80 "$V"; exit 1; }; echo "re-running once (load flakes): $F"; python3 tools/run_tests.py -j 2 $F > "$V.rerun" 2>&1 || { tail -80 "$V.rerun"; exit 1; }; for m in $F; do sed -i -E "s/^FAIL( +$m )/ok\1/" "$V"; done; }; for m in hub.tests.test_a2p_admin_browser hub.tests.test_a2p_bar_browser hub.tests.test_ui hub.tests.test_sessions_ui hub.tests.test_c1a1_browser hub.tests.test_anonymity hub.tests.test_image_imports; do grep -qE "^ok +$m " "$V" || { echo "MISSING OR FAILED $m"; grep -E 'FAIL|not ok' "$V" | head -10; exit 1; }; done; ! grep -qE '^FAIL +|^not ok' "$V" || exit 1; ! grep -vE '^[[:space:]]*(//|/\*|\*)' hub/static/views/adminsession.js | grep -qE 'XMLHttpRequest|sendBeacon|[.]fetch\(|innerHTML|iframe|form.submit' || { echo 'FORBIDDEN CROSS-ORIGIN CALL SHAPE in adminsession.js'; exit 1; }; grep -qE 'target: *"admin", *project' hub/static/views/adminsession.js || { echo 'admin stop body missing'; exit 1; }; grep -q 'onerror=alert' hub/tests/test_a2p_admin_browser.py || { echo 'hostile img marker missing'; exit 1; }; grep -q "$(printf '\342\200\256')" hub/tests/test_a2p_admin_browser.py || { echo 'hostile bidi marker missing'; exit 1; }; git diff --name-only delegate/a2p-1-bar-dropdown | grep -qvE '^(hub/static/views/(adminsession|sessions)[.]js|hub/static/app[.]css|hub/tests/(test_a2p_admin_browser|test_ui|test_sessions_ui)[.]py)$' && { echo 'a2p-2 touched files outside its scope'; exit 1; }; grep -E '^run_tests:' "$V"
```
2. Every row of the table above exists as a named test and passes; the URL table passes in the
   unit block of the module.
3. The scope guard passes; nothing under `daemon/`, `launcher/`, `hub/*.py` (non-test) changed.
4. Screenshots of every state while working (evidence dir), all read; the UI rules file followed.

## Out of scope

A2a step 6's options fields (consumed, never added); the admin page itself (a2a-9 — its
`?project=` consumption is that step's test); the acceptance screenshots (step 3); extend/restart
UI (a GET never starts, nothing on the hub origin extends); the bar dot (design §9-2, picked no).

## Host traps

Design §10. This step's own trap: the launcher relays `deadline` in **seconds** — a test that
renders `until 07:30` from a fixed epoch pins it; never read `Date.now()` twice into one assertion.
And: the fake launcher answers *one line per command line*, so a Stop's follow-up status poll
needs its answer queued in the FIFO first (the C1A1 callable-answer world model is why).
