# A2P step 1 — the ruling-24 bar: two buttons on top, the dropdown its own surface

Status: ready. Chain: `a2p-chain.json` step `a2p-1-bar-dropdown`. Light step (builds no URLs,
renders no *new* server strings — it re-renders today's in new containers); verify = the step's
modules + the scope guard. Read first: `docs/specs/a2p-design.md` (all of it), `docs/specs/a2-design.md`
§5.2/§7 rulings 24–26, commit `6eed48f` (project select closes the picker and never opens it —
law), the UI-verification rules (`~/.config/opencode/rules/verify-ui.md`), and the current code:
`hub/static/views/sessions.js`, `hub/static/views/claude.js`, `hub/static/index.html`,
`hub/static/app.css`, `hub/tests/test_ui.py::TestSessionPickerInSource`,
`hub/tests/test_sessions_ui.py`.

## Goal

The chat bar carries, on top and side by side, the session-dropdown control (today's
`#chat-project`, unchanged in id and behaviour), **New Claude session**, and **New admin
session**; the admin control renders disabled with its reason because the data that enables it
arrives in step 2. "New OpenCode session" is a dropdown row. The panel's structure, geometry and
Escape/focus contract stay exactly as `6eed48f` left them.

## Files owned

- `hub/static/index.html` — the bar row becomes `<div class="chat-bar">` wrapping the existing
  `#chat-project` button plus two new siblings, shipped bare:
  `<button id="claude-new" class="claude-btn bar-action" type="button" hidden>New Claude
  session</button>` and `<button id="a2p-admin-new" class="claude-btn bar-action" type="button"
  aria-disabled="true" title="Needs the admin origin: A1 phase 2">New admin session</button>`. The
  hand-off anchor `<a id="a2p-admin-link" rel="noopener" hidden></a>` ships here too (step 2 wires
  it; with no `href` it is inert and unfocusable). No inline style, no script (CSP + the fence).
  Narrow-label spans (`bar-wide`/`bar-narrow`) live inside each control.
- `hub/static/views/sessions.js` — `newRow` text becomes exactly `New OpenCode session` (drop the
  label argument); `EMPTY_NOTE` becomes `No sessions yet`; the bar paint sets `#chat-project`'s
  `aria-label` to `Sessions for <project>` (`Sessions` with no selection); `CLICK_AWAY_EXEMPT`
  grows to `"#session-picker, #chat-project, #claude-new, #a2p-admin-new, .project-item,
  #tabbar"`; the delegated click handler routes `#a2p-admin-new` to the `adminsession.js` seam;
  the epoch/signature guards keep working unchanged.
- `hub/static/views/adminsession.js` — **new module; this step writes only its seam**: exported
  `handleAdminClick(state)` (this step: open the dropdown, nothing more) and the copy constants
  `DISABLED_NO_ORIGIN` = `Needs the admin origin: A1 phase 2`, `DISABLED_OFF` = `Project admin is
  off: enable project_admin in admin.json`, `DISABLED_UNBROKERED` = `Not in broker.json`. Step 2
  fills in the rest. Justification: step 2 must not re-touch the markup or the bar's event wiring.
- `hub/static/views/claude.js` — the start control moves out of the section: `paintSection` no
  longer renders the `.claude-new` row; a new exported `renderBar(state)` drives `#claude-new`
  (hidden unless `claudeAvailable(state, state.selected)`; hidden when a session exists — the
  section names its state; `dev.busy === name` → `disabled` + text `Starting…`; otherwise enabled,
  `New Claude session`) and moves the permission-mode `.claude-modes` select into the bar beside
  it, shown only while no session exists and the launcher sends modes (values, labels and
  `aria-label="Permission mode"` unchanged); clicking the button posts exactly today's start with
  the current mode; the login-needed row, status, hint, terminal, stop and error stay in the
  section as today. `claudeSignature` gains the bar's visible state so the repaint rides the
  existing guard.
- `hub/static/app.js` — import `adminsession`? no: import nothing new except one `claudeView.renderBar(s)`
  call beside the existing `sessionsView.render(...)` in the render loop, and the bar-click hook is
  wired inside `sessions.js`'s own delegated listener. (One added line; the static fence re-grep
  is listed under Acceptance.)
- `hub/static/app.css` — `.chat-bar` (flex row; `.chat-bar .chat-project { flex: 1 1 auto;
  min-width: 0; ... }` keeps the pinned tokens on the button itself), `.bar-action` (the two
  controls, `.claude-btn` family, right side, `min-height: var(--touch)`),
  `#claude-new[disabled]`, and inside `@media (max-width: 640px)` the narrow swap
  (`.bar-wide { display: none }`, `.bar-narrow { display: inline }`) with the reverse outside.
  Buttons stay 44 px targets; the caret control ellipsizes; nothing overflows 390 px.
- Tests (pinned, named): `hub/tests/test_ui.py` (the static fence: §6 of the contract — the
  `setAttribute` allowlist, the `.textContent` allowlist, the markup and CSS greps),
  `hub/tests/test_sessions_ui.py` (row/empty strings; `test_the_picker_lists_the_projects_sessions_
  newest_first` expects `New OpenCode session` first and `No sessions yet` for the empty repo;
  `_select_project`/`_bar` keep working — the bar id did not move; the Escape-focus test stays
  untouched), `hub/tests/test_c1a1_browser.py` (its `.claude-start` clicks become `#claude-new`,
  its `.claude-modes` selector moves to the bar, the `picker-head` assertion becomes
  `["Claude", "OpenCode"]`; every other assertion word-for-word), `hub/tests/test_h3_browser.py`
  (the `New session` substring expectation follows the rename), and the new
  `hub/tests/test_a2p_bar_browser.py` (stack helpers copied from `test_sessions_ui.py`; no
  launcher needed).

## Contract (what a reviewer checks line by line)

1. Order and identity: `#chat-project`, `#claude-new`, `#a2p-admin-new`, then the inert
   `#a2p-admin-link`, all inside `.chat-bar`. The ids are exactly these — the a2a specs name them
   and the later steps must not rename.
2. Nothing about opening changes: the dropdown opens only from `#chat-project`; selecting a
   project closes it (`test_choosing_a_project_leaves_the_picker_closed_and_the_bar_opens_it`
   stays green **unmodified**); clicking the open bar closes it; Escape closes and focuses
   `#chat-project` (existing test unmodified); click-away exempts the new ids.
3. `#a2p-admin-new` renders `aria-disabled="true"` and is *not* `[disabled]` — a
   property-disabled control is unfocusable and its reason unreachable — with the pinned title.
   Activating it opens the dropdown (the reason *line* arrives with step 2's section; until then
   the dropdown shows today's contents). It stays that way on every state this base can reach,
   because the launcher status has no `project_admin` field yet — a missing field is off, never
   assumed on.
4. `#claude-new` is the one way to start a Claude session from the picker after this step; when
   `claudeAvailable` is false it is `hidden`, not disabled (a deployment without the launcher
   gets no dead control). The section's `.claude-new` row is gone; the section head text becomes
   `Claude` (the "· Remote Control" tail moves to the section's `aria-label`, already
   `Claude Remote Control`).
5. Copy exactly as pinned (design §5). The three disabled strings are exported constants, and a
   test greps them from `adminsession.js` by name.
6. The static fence moves with the code and only with it: allowed `setAttribute` names become
   `["aria-disabled", "aria-expanded", "aria-hidden", "aria-label", "data-action", "data-session",
   "title"]`; still no `href`/`src`/`style`/`dataset`; the `.textContent =` allowlist gains the
   bar/label expressions it needs (the ones added must themselves be literals or `String(...)`);
   the data-attribute count assertion counts 3 (`data-action` × 2, `data-session` × 1) and holds;
   `item.title` stays read 4 times in `sessions.js`; the CSS test re-greps `.chat-bar
   .chat-project` for `height: 32px` / `font-size: 13px` and keeps every `.session-picker` token;
   the markup test asserts the two new ids exist and `#session-picker` still ships empty.

## Behaviour and edge cases

- No project selected: the bar is hidden as today; with it hidden the row shows no half-bar
  (both new controls follow `#chat-project`'s hidden rule in `renderBar`/`render`).
- A project with no OpenCode pairing (H3 notice): notice path unchanged; the admin control still
  renders disabled-with-reason — the admin door does not depend on the OpenCode pairing.
- 10 000-char project name: the bar control ellipsizes; `aria-label` carries the raw string (the
  test asserts its length, not a truncation).
- Light and dark: nothing new is coloured beyond `.claude-btn` tokens; the screenshots are step 3.
- A11y spot checks in this step's browser test: Tab reaches all three controls in order, Space
  activates the bar, Escape returns focus; `aria-expanded` flips on `#chat-project` only.

## Acceptance criteria

1. Verify — exactly the chain's step-1 command (step's own modules through the parallel runner,
   scope guard against the base; light step, the hard gate runs at steps 2 and 3):

```
set -o pipefail; V="${DELEGATE_EVIDENCE_DIR:-/tmp}/verify-a2p1.log"; M="hub.tests.test_a2p_bar_browser hub.tests.test_sessions_ui hub.tests.test_ui hub.tests.test_c1a1_browser hub.tests.test_h3_browser hub.tests.test_anonymity hub.tests.test_image_imports"; python3 tools/run_tests.py $M > "$V" 2>&1 || { F=$(grep -E '^FAIL +' "$V" | awk '{print $2}' | tr '\n' ' '); [ -n "$F" ] || { tail -80 "$V"; exit 1; }; echo "re-running once (load flakes): $F"; python3 tools/run_tests.py -j 2 $F > "$V.rerun" 2>&1 || { tail -80 "$V.rerun"; exit 1; }; for m in $F; do sed -i -E "s/^FAIL( +$m )/ok\1/" "$V"; done; }; for m in $M; do grep -qE "^ok +$m " "$V" || { echo "MISSING OR FAILED $m"; grep -E 'FAIL|not ok' "$V" | head -10; exit 1; }; done; ! grep -qE '^FAIL +|^not ok' "$V" || exit 1; git diff --name-only a2-steps-6-8 | grep -qvE '^(hub/static/(index[.]html|app[.]js|app[.]css)|hub/static/views/(sessions|claude|adminsession)[.]js|hub/tests/(test_ui|test_sessions_ui|test_c1a1_browser|test_h3_browser|test_a2p_bar_browser)[.]py)$' && { echo 'a2p-1 touched files outside its scope'; exit 1; }; grep -E '^run_tests:' "$V"
```
2. The new browser test proves, at 1440×900 and 390×800: the three controls exist in order with
   the exact (short at 390) texts, `#chat-project` still toggles with `aria-expanded` flipping,
   `#a2p-admin-new` is `aria-disabled="true"`, never `disabled`, with the pinned title; clicking
   it opens the dropdown and changes nothing else; a project click closes the dropdown with the
   bar buttons untouched.
3. `git diff --name-only` touches only Files owned.
4. UI rule respected: screenshots of the bar at 390×800 and 1440×900 light and dark taken while
   working (worker's evidence dir), all read, layout gaps fixed before finishing.

## Out of scope

Any admin *enabled* state, the URL, the hand-off click behaviour, the admin row, status poll
changes, the acceptance screenshots (step 3). No hub/daemon/launcher code. No options fields —
A2a step 6 sends them; here a missing field is simply off.

## Host traps

Design §10 in short: host umask 002 and an exported `XDG_CONFIG_HOME` (tests write their own
config with explicit modes); never run history-changing git; `hub/tests/test_anonymity.py` scans
tracked files for site values — keep fixtures on `admin.example.com`; free ports only
(`httputil.free_port()`); run long suites detached (`setsid -f`), never as a job that ignores
SIGINT.
