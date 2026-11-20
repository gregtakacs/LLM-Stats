# a2p-3 — screenshot acceptance at both viewports and themes, full gate

Authority for this step: `docs/specs/a2p-design.md` §9 (the mechanism), §4
(the 390 px rule), §7 (anonymity). This is the slice's last step: it runs the
full gate and is allowed to touch product files **only for polish** found by
its own screenshots.

## Goal

One browser module, `hub/tests/test_a2p_browser.py`, that drives the finished
picker to the eight PNGs the slice is accepted on, asserts the phone layout
from the DOM (not the pixels), and fails — never skips — when chromium or a PNG
is missing. Plus the slice-level polish pass the screenshots justify.

## Read first

`docs/specs/a2p-design.md` §9; `hub/tests/test_h2_browser.py` (the chromium
discovery `CHROME`/`SKIP_REASON` pair and `PageSession`: `wait_for`,
`screenshot`, `set_store`, the `Emulation.setDeviceMetricsOverride` mobile
path, dark via `Emulation.setEmulatedMedia` — see how `test_h2c_browser.py`
takes its phone shots); `hub/tests/browser_front.py` (what
`PageSession.screenshot` does and the `DELEGATE_EVIDENCE_DIR` gate — this test
does **not** use it for naming, see below); `docs/specs/a2h-4-picker-life.md`
for the seeded-daemon fixture pattern in `test_a2h_seed_browser.py`.

## Files owned

- `hub/tests/test_a2p_browser.py` — new: the eight-PNG acceptance module.
- `hub/static/app.css` — polish only (the 390 px rule proved wrong, a dark-mode
  token, an ellipsis edge case).
- `hub/static/views/sessions.js`, `hub/static/index.html` — polish only, DOM
  shape frozen by steps 1–2's tests.
- `docs/specs/a2p-3-screenshots.md` (this file).

## Contract

1. **Fixture** — a hub + fake daemon through the standard
   `browser_front`/`test_h2_browser` stack, seeded (same helper style as
   `test_a2h_seed_browser.py`) so the selected project `code.example.com` has:
   two OpenCode sessions (titles `Review the failing tests`,
   `<img src=x onerror=alert(1)>` — hostile by design), two claude sessions on
   host `hub.example.com` (one running), one running admin status entry with a
   future deadline, and `options.project_admin` true, the project in
   `admin_projects`, host row `admin_origin` `https://admin.example.com`.
2. **The eight PNGs** — for each viewport `(390, 800)` and `(1440, 900)`, each
   scheme `(light, dark)` (`Emulation.setEmulatedMedia` with
   `features: [{name: "prefers-color-scheme", value: <scheme>}]` as
   `test_h2c_browser.py` does), each state `(closed, open)`: navigate, log in
   via the front's cookie path, select the project, `click("#ap-toggle")` for
   `open`, `wait_for` the row text, screenshot. Output dir
   `os.path.join(os.environ.get("DELEGATE_EVIDENCE_DIR") or "/tmp",
   "a2p-shots")`; names exactly `<w>x<h>-<light|dark>-<closed|open>.png`; each
   PNG written by the test itself (a `PageSession.screenshot`-style helper
   pointed at the explicit path), each path printed after writing. A test that
   cannot launch chromium **fails** (`self.fail(CHROME_HINT)` — the
   `test_h2_browser` pattern, deliberately not `skipTest`). The **populated**
   list is what `open` shots show: the screenshot happens only after
   `wait_for` finds both OpenCode rows and the admin row by text — an empty
   dropdown is a failure, not a photo.
3. **Layout assertions from the DOM** (pixels are for the human, the gate
   checks the rules): at 390 px the bar's two commands compute to text
   `Claude +` / `Admin +`; `#chat-project-label` is clipped
   (`scrollWidth > clientWidth` for the long seeded title only — pin the
   short-name case as *not* clipped); `document.documentElement.scrollWidth <=
   clientWidth` (no horizontal overflow) with the dropdown open; every row
   `getBoundingClientRect().height >= 44`; the hostile title is one text node
   (`row.textContent` contains the full `<img src=x onerror=alert(1)>`, and
   `row.querySelector("img")` is `None`).
4. **PNG self-check** — after writing each, assert `st_size > 5_000` and that
   the file starts with the PNG magic; `setUp` (running after the shots
   sequence, so really: a final test method) asserts the eight expected names
   exist in the output dir, so a silently-missing shot fails the run even if
   the shot loop missequenced.
5. **Anonymity** — the module's fixtures use only `hub.example.com`,
   `code.example.com`, `admin.example.com`; `hub/tests/test_anonymity.py`
   (in the gate) stays green; grep the module's own source for the real
   hostname patterns it forbids before committing (the anonymity test already
   scans test sources — just keep it passing).
6. **Polish budget** — exactly the four product-file kinds above, and only for
   a defect this step's own screenshots or DOM asserts show; each such edit
   names the assert it fixes in the commit message.

## Acceptance criteria

- The eight PNGs exist under `$DELEGATE_EVIDENCE_DIR/a2p-shots/` (or
  `/tmp/a2p-shots/`) with the exact names, each > 5 KB, each path printed by
  the run; all eight were read by the worker (this is UI work — see the
  verify-ui rule below).
- `python3 tools/run_tests.py -j 2 hub.tests.test_a2p_browser` ok, and the step's
  verify — the **full** `python3 tools/run_tests.py` — exits 0 with the gate
  line present.
- The DOM asserts of §3 pass at both viewports, both schemes.
- `git diff` at the end touches only Files owned (the scope guard).

## Out of scope

New behaviour (steps 1–2 own it all), new files beyond the test module, any
daemon/hub Python, the broker page (`a2a-9`), A2b badges.

## Worker rules for this host (lead, 2026-11-19)

- **UI verification is mandatory**: follow `~/.config/opencode/rules/
  verify-ui.md` — screenshots at 390×800 and 1440×900, light and dark, **read
  every PNG** you take, in both states, before reporting. A layout defect you
  can see is a defect; do not ship it as "pixel-perfect deferred".
- Tests run through `python3 tools/run_tests.py`; while iterating run only
  `hub.tests.test_a2p_browser -j 2`; this step's verify runs the full suites once —
  don't duplicate it beforehand.
- **Never run git history or branch commands** — no `merge`, `commit`, `rebase`
  or `stash`; delegate saves the round, and a worker-made commit has produced
  objects the host repo could not see. The scope guard reads your `git diff`.
  Read-only git (`status`, `diff`, `log`, `show`) is fine.
- The gate also runs on the owner's host: **umask 002**, **`XDG_CONFIG_HOME`
  exported**. Do not code around either. Every test that creates a file the
  code checks for its mode sets that mode explicitly; every test that replaces
  `HOME` also sets (or removes) `XDG_CONFIG_HOME`, `XDG_DATA_HOME`,
  `XDG_STATE_HOME` under its temp dir. Never read or write the real home.
- New browser tests use free ports (`httputil.free_port()`), never fixed ones —
  the runner executes modules side by side.
- **Chromium missing = FAIL, not skip** (the task's rule, §2). If your sandbox
  genuinely lacks chromium, run everything else, mark this criterion NOT
  VERIFIED with the exact discovery error, and do not add a skip path to the
  test.
- **Anonymity** is part of the contract: `hub/tests/test_anonymity.py` (in
  the gate) rejects real hostnames in fixtures and output; use
  `hub.example.com`, `code.example.com`, `admin.example.com`.

