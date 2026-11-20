# Browser acceptance: eight screenshots and the keyboard walk

Slice a2p, step 3 of 3 (last step of the chain — `hard: true`, full gate). Screenshots are the
acceptance evidence for this UI slice: this step's verify fails, not skips, without a browser.

## Goal

Prove the finished picker end-to-end in a real browser exactly as a user meets it: capture the
eight mandated PNGs (two viewports × two colour schemes × dropdown closed/open) against fully
populated fixture data, walk the whole keyboard flow, re-check the phone width, and leave the
evidence where the orchestrator can read every PNG. Fixes, if the walk finds any, stay inside the
files a2p-1/a2p-2 own.

## Read first

- `docs/specs/a2p-design.md` §7, §8; the two prior step specs.
- `hub/tests/test_h2_browser.py` (BrowserStack/CHROME discovery, `SKIP_REASON`, `PageSession`,
  `PROJECTS`), `hub/tests/browser_front.py` (`FrontDevTools`: CDP eval, input dispatch),
  `hub/tests/test_c1a1_browser.py` (the existing picker screenshot test — names, sizes,
  `EVIDENCE_DIR` handling, `Emulation.setDeviceMetricsOverride` use),
- `hub/tests/test_sessions_ui.py` / `test_a2p_dropdown.py` (the fakes that feed the populated
  fixture: launcher status, hosts with `admin_origin`, relay sessions).

## Files owned

- create: `hub/tests/test_a2p_browser.py`
- modify (only to fix what the walk exposes): `hub/static/views/sessions.js`,
  `hub/static/views/running.js`, `hub/static/index.html`, `hub/static/app.css`,
  `hub/static/app.js`, `hub/static/state.js`

## Contract

- Exactly eight screenshots, CDP `Page.captureScreenshot`, full page (no clip), saved as
  `390x800-light-closed.png`, `390x800-light-open.png`, `390x800-dark-closed.png`,
  `390x800-dark-open.png`, `1440x900-light-closed.png`, `1440x900-light-open.png`,
  `1440x900-dark-closed.png`, `1440x900-dark-open.png` into
  `${DELEGATE_EVIDENCE_DIR:-/tmp}/a2p-shots/` (the test creates the directory; the name pattern is
  `<w>x<h>-<light|dark>-<closed|open>.png` — verbatim, the verify script re-lists it).
- Scheme via `Emulation.setEmulatedMedia` `features: [{name: "prefers-color-scheme", value: …}]`
  before navigation, re-asserted in-page via `matchMedia`; viewport via
  `Emulation.setDeviceMetricsOverride` (deviceScaleFactor 2 phone, 1 desktop) exactly as
  test_c1a1_browser does.
- **This module never skips.** `CHROME is None` or an unreachable CDP target is a test failure with
  the message `browser required for a2p acceptance`; likewise any missing or <4 KiB PNG (asserted
  after each capture) and any PNG whose pixels are identical between light and dark (cheap guard:
  file bytes differ) — a scheme-blind screenshot proves nothing.
- Populated fixture, all surfaces live at once: signed-in session; project `app` selected;
  `/api/launcher/status` answering 200 `ok` with options `{dev:true, project_admin:true,
  permission_modes: […], agents: […], admin_projects:["app","www"], admin_members:{…}}` and two
  admin sessions (`{target:"admin", project:"app", agent:"claude", state:"idle", timed:true,
  deadline:<+41min>, link:…}` and one `busy` untimed on `www`); three OpenCode sessions for `app`
  (normal titles + one ≥120-char title); hosts fixture `admin_origin` valid. `open` shots show the
  dropdown with both sections and the New OpenCode session control.

## Behaviour and edge cases (each a test in the module)

1. Eight captures in the mandated names, each re-read: exists, ≥4 KiB, PNG magic bytes `89504e470d0a1a0a`.
2. At 390×800 with the dropdown open: `documentElement.scrollWidth <= innerWidth`; both bar labels
   present verbatim in `textContent` even where visually clipped.
3. Keyboard walk from a fresh load, Tab from the bar: Tab reaches both buttons (no trap), Enter
   opens, ArrowDown enters the first row, arrows reach Stop/Retry/New OpenCode session, Escape
   closes with focus back on `#picker-toggle`, `aria-expanded` flips each step (assert after each
   keystroke, not at the end).
4. Mouse parity: same open/close cycle by click, and click-away closes.
5. The Stop button appears on the live row and, confirmed through the fake, POSTs the exact body
   (parity check with step 2's test — regression pin against step 3's own fixes).
6. Dark scheme shows the dropdown (computed `--panel` differs from light — one assertion proving
   the emulated media took effect before capture).

## Acceptance criteria

- `python3 tools/run_tests.py` (both suites, full) green; verify's own `ls`/`test -s` over the
  eight filenames passes from the shell after the run; scope guard clean.
- The orchestrator host reads all eight PNGs (AGENTS/verify-ui.md) — the files, not this spec, are
  the evidence.

## Out of scope

Everything else. No new product behaviour: this step either reproduces steps 1–2's contract in the
mandated visual states or reports/fixedly-cites the gap. No video, no trace files, no flaky
pixel-diffing (magic bytes + size + one computed-style probe only).

## Notes

Keep one `PageSession` per viewport+scheme pair and re-capture after each state change; CDP
`captureScreenshot` needs `fromSurface:true` and a settled frame (the existing harness waits for
idle — reuse it). Screenshot failures must name the exact missing filename.

## Worker rules for this host

- While working run only `python3 tools/run_tests.py hub.tests.test_a2p_browser`; run the full
  `python3 tools/run_tests.py` once at the end (this is the chain's last step).
- Host traps: `umask 002`; export `XDG_CONFIG_HOME`; long suites via `setsid -f`; free ports only.
- Never run git merge/commit/rebase/stash/push. No site values (test_anonymity.py).
- Do not add skips anywhere: an environment without chromium fails this module by design — say so
  in the report instead of editing the guard.
