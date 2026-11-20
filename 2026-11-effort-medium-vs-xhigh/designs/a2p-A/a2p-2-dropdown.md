# a2p-2 — the dropdown: rows, one-shot OpenCode, admin section, states, keyboard

Authority for this step: `docs/specs/a2p-design.md` §2, §3, §5, §7. Upstream:
ruling 24 (source order, one-shot row), ruling 9 (OpenCode sessions have no
stop), a2a §7 + `docs/specs/a2a-3-units.md` (status entry), rulings 25–26
(`textContent` only; no new channel).

## Goal

Fill the dropdown that step 1 opened: the session list with its sections in
ruling 24's order, the one-shot `New OpenCode session` row with its pending
state, the running-admin section (state, deadline, Stop via
`POST /api/launcher/stop`, `Open` hand-off), and every state line from design
§3 — empty, loading, error+retry, not-in-broker, admin-off. End state: the
picker's whole behaviour exists; step 3 only proves it visually.

## Read first

`docs/specs/a2p-design.md` (§2 timing table, §3 copy, §7 trust); step 1's spec
(the bar/guard it builds on); `docs/specs/a2h-4-picker-life.md` (what
`POST /api/launcher/oc/start` does — autostart, touch); `docs/specs/a2a-3-units.md`
(the admin status entry: `project`, `state`, `deadline`, `rc_name`, `link`,
`member`); `hub/tests/test_sessions_ui.py` as rewritten by step 1 (fixtures and
style to copy); `hub/tests/test_h2c_browser.py` §6a (the real-daemon flow-test
pattern).

## Files owned

- `hub/static/views/sessions.js` — the dropdown body: sections, rows, states,
  stop wiring, keyboard model. `fetchProjectSessions`/`_oc_start`/`_startCreate`
  paths from step 1's picker extend, not fork.
- `hub/static/app.css` — row/section/state rules (`.session-row`,
  `.session-section`, `.session-empty` reused; `.ap-admin-state`,
  `.ap-stopped-note` new).
- `hub/tests/test_a2p_dropdown.py` — new: the DOM battery **and** the
  real-daemon flow test built on the `test_h2_browser.BrowserStack` (real
  daemon, real `hub serve`, headless chromium): seed the admin status entry
  through the daemon's status hook, tap Stop, assert from the daemon's request
  log that the stop call carried exactly `{"target": "admin", "project": P}` to
  `/api/launcher/stop`, and that the row is gone on the next poll.
- `hub/tests/test_sessions_ui.py` — the body-test rewrite (the non-bar subset
  of step 1's list) plus any of its tests this step's re-layout retargets.
- `docs/specs/a2p-2-dropdown.md` (this file).

## Contract

1. **Sections and order** (design §1 sketch, ruling 24): `OpenCode` section
   first, then `Claude · {host}` (per host row that has sessions for the
   project — the existing host-order rules hold), then `Admin · {P}` last. A
   section header renders only when its rows or its state line render. Row
   text: OpenCode/claude rows are `{title}  {touched}  [Stop]` (claude only —
   ruling 9: **no Stop on an OpenCode row**, pin it); each group newest-touched
   first. `touched` renders `now`/`Nm ago`/`Nh ago`/`Nd ago` as today.
2. **One-shot OpenCode row** — appears under OpenCode only when the project has
   zero OpenCode sessions: `New OpenCode session in {P}`, a `→` affordance,
   `aria-haspopup="dialog"`. Tap: `POST /api/launcher/oc/start` with the project
   (existing `_oc_start` path), row shows `Starting…` and gets
   `aria-busy="true"`, second tap inert while pending; success closes the
   dropdown and opens the returned `link` (existing behaviour); failure → line
   `Could not start the session: {detail}.` (existing) with the row clickable
   again. The row disappears once a session exists there (re-paint from the
   list, design §2).
3. **Admin section** — rows exist only for `target == "admin"` status entries.
   Visible: project, state, deadline; buttons `Stop` and `Open`.
   - `running` → `running until {t}` (design §3 render rule; passed deadline →
     `until overdue`); `starting`/`stopping`/`exited (rc N)`/`gone`/
     `launch-failed` render the state string as reported.
   - `Stop` → confirm (`confirm()` with the §3 text; a test stub answers, the
     a2h-6 pattern), then `POST /api/launcher/stop` body
     `{"target":"admin","project":P}` — the exact body the flow test asserts —
     then the next status poll repaints. Failure → `Could not stop it:
     {detail}` + `Dismiss`, note clears on Dismiss or next successful poll.
   - `Open` → design §6 hand-off on the entry's `link` (top-level,
     `rel="noopener"`, never fetch/iframe).
   - The selected project not in `options.admin_projects` → line `Not in
     broker.json: no admin sessions for this project.` in place of rows.
     `options.project_admin` false → line `Admin sessions are off.`.
4. **States** — loading: opening a project whose sessions are not cached yet
   renders `Loading…` under the heading (a string step 2 adds to design §3's
   table; it is state, not copy drift). Error: `Could not list these
   sessions.` + `Retry` that refetches. Empty: `No sessions here yet.`. The
   admin section's absence is never an error — a project with no admin session
   renders no Admin section, and the bar button state (step 1) is what says why
   you can't start one.
5. **Trust** — design §7: every server string via `textContent` only. The test
   battery feeds `<img src=x onerror=alert(1)>`, `U+202E` (a title that starts
   with the RTL override), a 10 000-char title and a title of ` `-shaped
   lookalikes, and asserts: text rendered, row clipped (`overflow:hidden` +
   `text-overflow:ellipsis`, computed), no extra element under the row
   (`children.length`), no script executed (`window.__xss` stays unset — the
   fixture title carries `onerror="window.__xss=1"` form), row still clickable
   and tabbable.
6. **Keyboard** — design §5: ArrowUp/Down walk within the dropdown's focusable
   controls (rows and buttons alike, DOM order), Home/End first/last, Enter/
   Space activate, Escape close+focus caret, Tab off last control closes. While
   closed: no roving tabindex, no key handlers active.
7. **Repaint stability** — the signature (`sig`) covers project, list versions,
   status version, pending/creating flags; a poll whose versions match paints
   nothing; a poll that does paint keeps DOM focus inside the dropdown on the
   same control identity (the moved-step version of
   `test_a_background_poll_never_steals_the_panel_or_the_focus`).

## Acceptance criteria

- `python3 tools/run_tests.py -j 2 hub.tests.test_a2p_dropdown
  hub.tests.test_sessions_ui hub.tests.test_a2p_bar` exits 0 with each
  summary line `ok`.
- The verify (chain JSON) runs the full suite and greps the evidence log for the
  gate line and the new module.
- The stop POST body the flow test observes is exactly
  `{"target": "admin", "project": "<name>"}`.
- `git diff` outside Files owned: empty (the scope guard in the verify).

## Out of scope

The screenshot test (step 3), bar changes (step 1), any daemon/hub Python
change, any new endpoint, per-frame badges (A2b).

## Worker rules for this host (lead, 2026-11-19)

- Tests run through `python3 tools/run_tests.py`; while iterating run only this
  step's modules; run the full suites once, at the end — this step's verify
  runs them too.
- **Never run git history or branch commands** — no `merge`, `commit`, `rebase`
  or `stash`; delegate saves the round, and a worker-made commit has produced
  objects the host repo could not see. The scope guard in this step's verify
  reads your `git diff`. Read-only git (`status`, `diff`, `log`, `show`) is fine.
- The gate also runs on the owner's host: **umask 002**, **`XDG_CONFIG_HOME`
  exported**. Do not code around either. Every test that creates a file the
  code checks for its mode sets that mode explicitly; every test that replaces
  `HOME` also sets (or removes) `XDG_CONFIG_HOME`, `XDG_DATA_HOME`,
  `XDG_STATE_HOME` under its temp dir. Never read or write the real home.
- **Anonymity**: `hub/tests/test_anonymity.py` is in the gate; fixtures use
  `hub.example.com`, `code.example.com`, `admin.example.com`, never a real
  hostname.
- New browser tests use free ports (`httputil.free_port()`), never fixed ones —
  the runner executes modules side by side.
- If chromium cannot launch, a screenshot test must **fail**, not skip.
- The flow test's daemon and hub are the real ones from the
  `test_h2_browser.BrowserStack`; it is that module's `fake_claude` the admin
  command points at; never point anything at a real `~/.claude` — the stack
  keeps every home in its own temp root, keep it that way.

