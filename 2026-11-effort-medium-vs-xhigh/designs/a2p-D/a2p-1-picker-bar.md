# The picker bar: two controls, launcher state plumbing, dropdown skeleton

Slice a2p, step 1 of 3. Base: everything through a2p-design.md §1, §2, §5, §6. No server strings
render into the DOM in this step (that is step 2), which is why this step is `hard: false`. The
server-side inputs (`admin_projects`-shaped options, per-project status entries, the a2a-9 receiver)
are pinned by the specs the design preamble names; this chain is scheduled after those merge.

## Goal

Turn `#chat-project` into the ruling-24 bar: **New Claude session** + **New admin session** real
`<button type="button">`s, the second being the dropdown's only toggle (`aria-expanded`,
`aria-controls="session-picker"`); give the page the launcher-status and project data the bar and
dropdown need (`launcherStatus`, `pickerProjects` in state.js, polled like running.js already
polls); paint every bar state incl. the three verbatim disabled reasons; restructure
`#session-picker` into the three sections with the header text moved from the bar label into the
dropdown header; style it all with existing tokens so 390px fits with no horizontal scroll.

## Read first

- `docs/specs/a2p-design.md` §1, §2, §5, §6, §7 — binding, copy verbatim.
- `docs/specs/a2a-design.md` §7 (picker contract, lines ~725–750) and `docs/specs/a2-design.md`
  rulings 9, 24–26.
- `hub/static/index.html` (bar + picker markup today), `hub/static/views/sessions.js` (open/close,
  `CLICK_AWAY_EXEMPT`, keyboard, `paintBar`-equivalent around line 385), `hub/static/views/running.js`
  (the 10s status poll, STATE_WORDS, deadline text — the pattern to mirror, not yet to import),
  `hub/static/state.js`, `hub/static/app.js` (`setPickerOpen` on project select — commit `6eed48f`,
  keep; `renderAdminLink` reading `admin_origin` from `/api/hosts`), `hub/static/app.css`
  (`.chat-project`, `.session-picker`, `.claude-btn`, tokens).
- `hub/tests/test_ui.py` (static contract around line 1242 — you update it), `hub/tests/test_sessions_ui.py`
  (browser pattern: h2b stack, DOM expressions over CDP, `dispatch_key`/`dispatch_mouse`), and
  `hub/tests/test_c1a1_ui.py` (static grep house style).

## Files owned

- modify: `hub/static/index.html` — bar container + two buttons + section skeleton inside `#session-picker`
- modify: `hub/static/app.css` — bar layout, `.picker-btn`, section classes, ellipsis rules; existing tokens only
- modify: `hub/static/state.js` — `launcherStatus`, `pickerProjects` keys
- modify: `hub/static/app.js` — poll `GET /api/launcher/status` + `GET /api/oc-projects` alongside the bar's visibility, feed state; keep `pickerOpen:false` on project select
- modify: `hub/static/views/sessions.js` — bar painting incl. §2 state table (reason strings as constants), `aria-disabled` handling, Escape/focus-restore, `CLICK_AWAY_EXEMPT`, section skeleton render (static parts only)
- modify: `hub/tests/test_ui.py` — the static picker contract assertions become the new markup (keep the `aria-controls`/`aria-expanded` pins, add `picker-new-claude`/`picker-toggle`, no `<select>`, no inline handler)
- create: `hub/tests/test_a2p_bar.py` — browser checks for everything below

## Contract

- DOM ids/classes exactly as design §1. Bar visible exactly when it is today (`BAR_HIDDEN`
  expression unchanged).
- `launcherStatus = {phase: "loading"|"ready"|"error", sessions: [], options: {}, error: null}`;
  poll 10s while the bar is visible, refresh on view entry and after Stop (Stop lands step 2;
  expose the refetch hook now). HTTP 503 whose body carries `error: "launcher_unavailable"` is the
  **unreachable** face (design §5); any other non-OK or a transport failure is the **error** face.
- State table §2 painted on every state change; all copy constants verbatim:
  `New Claude session`, `New admin session`, `New OpenCode session`, `Claude sessions`,
  `OpenCode sessions`, `Not in broker.json`,
  `Needs the admin origin: A1 phase 2`,
  `Claude sessions are managed from the admin page.`, `No Claude sessions`,
  `Claude sessions: loading…`, `Claude sessions: launcher unreachable`,
  `Claude sessions: unavailable — Retry`.
- Reason display: `aria-disabled="true"` + `title=reason` on the button + the same reason as a
  visible `.picker-admin-note` line inside the opened dropdown (§3 order); never native `disabled`.
- Origin validation helper `safeAdminOrigin(value)` per design §4 lives in sessions.js and is the
  single gate: step 2's hand-off consumes it.

## Behaviour and edge cases (each a test in test_a2p_bar.py)

1. Signed in with a project: bar shows exactly the two buttons, verbatim textContent, both Tab-reachable, caret not focusable separately.
2. Never opens on project select: selecting a project keeps `aria-expanded="false"`, picker `hidden`, and closes an open one (extends the existing 6eed48f pin).
3. Toggle opens/closes by click, Enter and Space; `aria-expanded` mirrors; Escape closes and returns focus to `#picker-toggle` (assert `document.activeElement`).
4. Click-away closes; clicking inside `#session-picker` does not.
5. Bar states: options with `project_admin: true` + project in `admin_projects` + `admin_origin: "https://admin.invalid"` from the hosts fixture → both buttons enabled, none `aria-disabled`.
6. Each disabled reason in isolation: hosts fixture `admin_origin: null`, then `"http://x.invalid"`, then `"https://x.invalid/p"`, then `"https://u:x@x.invalid"`, then `"not a url"` → button aria-disabled, `title` and visible dropdown line carry `Needs the admin origin: A1 phase 2` exactly; fixture without the selected project in `admin_projects` → `Not in broker.json`; `options.project_admin` absent/false → `Claude sessions are managed from the admin page.`. A click on each does nothing (no navigation — URL unchanged; no request to the admin origin in the fake's log).
7. Launcher status states: request slow → dropdown Claude section shows the loading copy; 503 `launcher_unavailable` → `Claude sessions: launcher unreachable`; HTTP 500 → `Claude sessions: unavailable — Retry`, and the Retry button refetches (fake counts calls); buttons the §2 table says are unaffected stay usable.
8. 390×800: `documentElement.scrollWidth <= window.innerWidth`, both buttons' `textContent` still exactly the verbatim strings while computed style may clip (`overflow:hidden`, `text-overflow:ellipsis`).
9. The bar renders no server strings: with hostile fixtures set on the fakes, `#chat-project` textContent is exactly the two labels (defense-in-depth pin).

## Acceptance criteria

- `python3 tools/run_tests.py hub.tests.test_a2p_bar hub.tests.test_ui hub.tests.test_anonymity` green; the module-ok greps in the chain verify pass.
- test_ui's updated static contract asserts the new markup and still forbids inline script/style and `<select>`.
- `git diff` touches only Files owned.

## Out of scope

Admin session rows, Stop, hand-off navigation/encoding, injection tests (step 2); screenshots and
the keyboard walk (step 3); claude.js (ruling 25: A2d); OpenCode create-path changes (design §3.3).

## Notes

The three disabled reasons are the whole accessible-failure UX of this slice: a `title` alone
fails keyboard-only users, a visible line alone fails announcement — the belt pair plus
`aria-disabled` is the chosen mechanism (design §2); do not substitute native `disabled`.

## Worker rules for this host

- Run only `python3 tools/run_tests.py hub.tests.test_a2p_bar hub.tests.test_ui hub.tests.test_anonymity` while working; the harness re-verifies.
- Host traps: `umask 002`; export `XDG_CONFIG_HOME`; long suites via `setsid -f`, never SIGINT-ignoring background jobs; new tests use free ports (`bind(("127.0.0.1", 0))`).
- Never run git merge/commit/rebase/stash/push; no site values anywhere (test_anonymity.py).
- No `innerHTML` anywhere in picker code paths.
