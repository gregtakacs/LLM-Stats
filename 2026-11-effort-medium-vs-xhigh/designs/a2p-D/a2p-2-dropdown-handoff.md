# Dropdown contents, admin session rows, Stop, and the hand-off URL

Slice a2p, step 2 of 3. Builds directly on a2p-1 (bar, state plumbing, skeleton, `safeAdminOrigin`).
`hard: true`: this step renders server-supplied strings into the DOM and builds cross-origin URLs.

## Goal

Fill the dropdown's Claude section with live admin sessions and every section state's row; wire
**Stop**; make **New Claude session** navigate via the validated hand-off URL with the project name
encoded exactly once; keep **New OpenCode session** on today's pinned relay-create path; prove the
whole hostile-string surface (XSS marker, U+202E, 10 000 chars) renders as clipped text and adds no
element. Design §3 and §4 are binding; all copy verbatim from the a2p-1 constants list.

## Read first

- `docs/specs/a2p-design.md` §2–§5, §7; `docs/specs/a2p-1-picker-bar.md` (skeleton and helpers as
  built).
- `docs/specs/a2h-design.md` §7 (`/api/launcher/status` answer shape: `sessions[]` entries with
  `target/project/agent/state/deadline/timed/started/rc_name/link/member`, `options` incl.
  `project_admin`, `admin_projects`, `admin_members`) and `docs/specs/a2h-4-picker-life.md`.
- `docs/specs/a2a-9-admin-page.md` (the receiving side: `?project=&agent=` pre-fill; note the card
  never puts a member into the link — neither does the picker).
- `hub/static/views/running.js` (STATE_WORDS, deadline text, Stop with inline confirm, the stop
  POST body — mirror its semantics), `hub/static/views/sessions.js` as a2p-1 left it,
  `hub/tests/test_sessions_ui.py` (fixtures, `dispatch_key`, fake relay logs),
  `hub/tests/test_a2a_admin_browser.py` (how the admin fakes record requests).

## Files owned

- modify: `hub/static/views/sessions.js` — admin rows, section state rows, Stop, hand-off click, `handoffUrl()`
- modify: `hub/static/views/running.js` — export the state-word and deadline-text helpers (behaviour unchanged; running.js internals import them)
- create: `hub/tests/test_a2p_dropdown.py`
- modify: `hub/tests/test_sessions_ui.py` — only where the bar/dropdown restructure breaks pinned scenarios (row counts, ids, copy); never weaken a scenario, update its expectations
- modify: `hub/tests/test_ui.py` — static contract additions below

## Contract

- **Hand-off.** `handoffUrl(origin, project, agent)` per design §4: trailing `/` stripped,
  `"?project=" + encodeURIComponent(project) + "&agent=" + agent`, nothing else in the query. The
  New Claude session click (enabled state only) calls `location.assign(handoffUrl(origin, P,
  "claude"))`. No `window.open`, no anchor, no `fetch`, no `XMLHttpRequest`, no iframe anywhere in
  hand-off code (verify greps). `agent=opencode` exists in the builder and is exercised by test
  (the dropdown's row-level OpenCode hand-off stays dormant until A2e — test the builder).
- **Admin rows.** One `.admin-session-row` per status entry `target == "admin"`, newest first, all
  fields via `textContent`; state words and deadline text come from the helpers exported by
  running.js (no duplication). Row click (or its `.admin-session-open` button) opens the entry's
  `link` top-level — same rules, and only because that link is daemon-produced same-
  hub-origin; Stop = running.js's inline-confirm pattern (`Stop`, re-click inside the timer says
  `Really stop?`, mirroring admin.js) → `POST /api/launcher/stop`
  with exactly the body running.js's `stopBody()` builds for that entry (the helper is exported in
  this step and is the single builder; today that is `{"target":"admin"}` — project-free, since
  `hub/adminapi.py` `_validate_stop` rejects extra keys on non-dev targets) with the signed-in
  cookie; on 2xx re-poll status once
  immediately; on error paint the returned reason inline and keep the row.
- **Section states** (design §3.2 list, incl. Retry). `project_admin` off ⇒ the section is the
  reason line, not an error.
- **Encoding.** A project named `app'&x" /y%` must arrive at the admin origin with the raw query
  exactly `?project=app%27%26x%22%20%2Fy%25&agent=claude` (computed once, asserted literally).

## Behaviour and edge cases (each a test)

1. Two live admin sessions in the status fixture (idle timed with deadline, busy untimed) → two
   rows with agent word, project, state word, deadline text; the OpenCode section unchanged; header
   shows `Chat <P>` plus the live session's state.
2. Stop: click → confirm copy → POST body asserted byte-for-byte equal to `stopBody(entry)` from
   the fake's log → exactly one
   status refetch follows → row gone from the DOM after the refreshed answer.
3. Stop error: daemon answers `{"ok":false,"error":"not running"}` → reason visible inline, row kept, no throw.
4. Hand-off happy: hosts fixture `admin_origin: "https://admin.invalid/"`, enabled click → the fake
   admin origin logs exactly one GET, request target `/?project=app&agent=claude` (trailing-slash
   normalisation asserted), and the browser left the hub page (URL check). No POST, no other request.
5. Encoding: the `'&x"` project above; and a project containing `javascript:` as text — never becomes a URL scheme.
6. Origin rejection set (five values from a2p-1's test 6) → no navigation, one GET never hits the admin fake, reason line visible.
7. **Injection trio**, as the only titles/fields of the fixtures: `<img src=x onerror=alert(1)>`,
   `a\u202Eb.txt` (literal U+202E between the letters), and `"t".repeat(10000)` — on an OpenCode title, an
   admin project field and a member name. Assert: picker `textContent` contains the exact strings;
   `querySelectorAll("#session-picker img, #session-picker script").length == 0`; no alert fired (JS dialog hook);
   the long-title row's computed `overflow`/`text-overflow` clip and the dropdown's height does not
   grow with it.
8. Dropdown keyboard: ArrowDown from the toggle enters the first row, arrows walk all controls,
   Escape returns focus to the toggle (extends, not duplicates, step 3's fuller walk).
9. project switch while open: closed, fresh project's sections repainted from the new project's
   status entries only, stale data never renders.

## Acceptance criteria

- Full gate green; verify greps below pass; test_sessions_ui scenarios all still pass with updated expectations (none deleted).
- Static: `grep -q 'location.assign' sessions.js`; `! grep -nE 'window[.]open|XMLHttpRequest' sessions.js`; sessions.js contains `encodeURIComponent` exactly in `handoffUrl`; no `innerHTML` in sessions.js/running.js.

## Out of scope

Screenshots and the formal keyboard-walk acceptance (step 3); OpenCode hand-off flip (A2e);
claude.js (A2d); any server change — the status/stop endpoints already exist.

## Notes

The deadline text must be derived at paint time from `deadline`, never cached strings, matching
running.js so the two surfaces cannot disagree; that is why step 2 exports helpers instead of
copying them.

## Worker rules for this host

- While working run only `python3 tools/run_tests.py hub.tests.test_a2p_dropdown hub.tests.test_sessions_ui hub.tests.test_ui`; run the full `python3 tools/run_tests.py` once at the end.
- Host traps: `umask 002`; export `XDG_CONFIG_HOME`; long suites via `setsid -f`; free ports only.
- Never run git merge/commit/rebase/stash/push. No site values (test_anonymity.py).
