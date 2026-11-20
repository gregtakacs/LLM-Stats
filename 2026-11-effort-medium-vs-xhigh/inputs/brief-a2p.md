# A2P design: plan A2 step 7 (the unified picker UI) and write its step specs (no product code)

## Goal

Step 7 of `docs/specs/a2-design.md` (§7 "The unified picker", §8 row 7) as refined by the
owner's rulings 9 and **24–25** at the end of that file. Your job in this task is **design
only**: the slice design, a spec per step, and a `delegate chain` plan that other workers will
run step by step. Write no product code.

## Read first

- `docs/specs/a2-design.md`: §5.2 (the OpenCode address `/p/<project>/`), §7, ruling 9 and the
  "Step 7 and 8 rulings" (24, 25, 26) at the end. Rulings are binding.
- `docs/specs/a2a-design.md` §7 "The hub, and what the picker (step 7) gets": **the whole
  contract** the picker consumes (`/api/hosts` `admin_origin`, `/api/launcher/status`
  `options.project_admin` / `options.admin_projects` / `sessions[]` with `target == "admin"`
  and `project`, the hand-off link `<admin_origin>/?project=<urlencoded P>&agent=claude|opencode`,
  `POST /api/launcher/stop` `{"target":"admin","project":P}`, the disabled reasons and their copy
  text). Step 6 (`a2a-*`) is being built now on the same branch; treat its specs as the contract,
  do not read code it has not landed yet.
- `docs/specs/a2h-design.md` and `docs/specs/a2h-4-picker-life.md`: step 5's picker (what exists).
- The picker code today: `hub/static/views/sessions.js`, `hub/static/views/projects.js`,
  `hub/static/views/claude.js`, `hub/static/views/running.js`, `hub/static/state.js`,
  `hub/static/data.js`, `hub/static/app.css`, `hub/static/index.html`, `hub/oclife.py`.
  Commit `6eed48f` (`git show --stat 6eed48f`, then its diff of the views) is the
  "no auto-open on project switch" change: keep that behaviour.
- The existing UI tests to imitate and the ones that pin picker behaviour this slice changes:
  `hub/tests/test_sessions_ui.py`, `hub/tests/test_ui.py`, `hub/tests/test_h2c_browser.py`,
  `hub/tests/test_a2h_seed_browser.py`, `hub/tests/browser_front.py` (the browser harness and
  how screenshots are taken). Name each pinned test that must change in the step that changes it
  and put it in that step's scope.
- Earlier plans to imitate: `docs/specs/a2h-chain.json`, `docs/specs/a2a-chain.json` and their specs.
- The step-spec template: `~/{claude-dir}/skills/delegate/spec-template.md` (mounted read-only).

## The repo's gate

`python3 tools/run_tests.py`. Every step's verify ends with it, exactly as written here (imitate
how `docs/specs/a2a-chain.json` writes the verify: the gate's output into
`${DELEGATE_EVIDENCE_DIR:-/tmp}/verify-<step>.log`, then greps that the step's own test modules
ran `ok` and nothing failed).

## Fixed requirements

- Ruling 24 word for word: on top **New Claude session** and **New admin session**; the
  dropdown of existing sessions only on demand from its own control, never on project select,
  closed on project switch. "New OpenCode session" lives in the dropdown. Copy text for every
  button, label, disabled reason and empty state goes in the spec verbatim.
- The admin hand-off is a top-level navigation (`<a href>` with `rel="noopener"` or
  `location.assign`), never `fetch`/POST to the admin origin, never an iframe. The project name
  in the link is `encodeURIComponent`-encoded. `admin_origin` from `/api/hosts` is used only when
  it parses as an `https:` URL with no path, query, fragment or credentials; anything else
  disables the admin button ("Needs the admin origin: A1 phase 2").
- Project names, session titles, `rc_name`, `member` and any other server-supplied string are
  rendered with `textContent` (never `innerHTML`); a test feeds a title with `<img src=x
  onerror=…>`, bidi controls (U+202E) and a 10 000-character title and asserts it renders as
  text, clipped by CSS, with no new element.
- States, each with a test: launcher status unavailable or erroring (buttons the status does
  not decide stay usable, admin rows show the reason), no sessions (empty state copy), loading,
  a running admin session for the project (shown in the dropdown with state and deadline, and a
  Stop that calls `POST /api/launcher/stop` and refreshes), project not in `admin_projects`
  ("Not in broker.json"), `project_admin` off (not configured), no admin origin.
- Keyboard and a11y: both buttons and the dropdown control are real `<button>`s reachable by Tab,
  the dropdown is operable with Enter/Space/Escape/arrow keys, Escape returns focus to its
  control, `aria-expanded` reflects state, disabled buttons carry the reason in an accessible
  way (`aria-disabled` + visible reason or `title`, pick one and say why).
- Visual: imitate the existing bar's visual language (its colours, CSS variables, spacing,
  radius, font sizes in `hub/static/app.css`); no new colours outside the existing variables, no
  new dependency, no icon font. Light and dark both. It must fit at 390 px wide without
  horizontal scroll (the buttons may shorten their label at narrow widths: say how).
- **Screenshots are acceptance evidence.** The UI step's verify, after the gate, runs a browser
  test that saves PNGs of the picker bar closed and with the dropdown open, at 390×800 and
  1440×900, light and dark, into `${DELEGATE_EVIDENCE_DIR:-/tmp}/a2p-shots/` (8 files, named
  `<w>x<h>-<light|dark>-<closed|open>.png`), with a populated session list (fixture data), and
  fails if any is missing. Use the harness in `hub/tests/browser_front.py`; if the browser is
  missing the test must fail, not skip, in that step's verify (the sandbox has chromium).
- Host traps (put in every spec): the host runs umask 002 and exports `XDG_CONFIG_HOME`; tests
  that create files set their own modes and env, never touch the real home. Workers never run
  `git merge`/`git commit`/`git rebase`/`git stash`.
- No site values (host names, domains, addresses) anywhere: `hub/tests/test_anonymity.py`.

## What to write

1. `docs/specs/a2p-design.md`: what the slice adds mapped to §7 and rulings 9/24/25; the
   picker's state model; data it reads and when it refreshes; copy text; layout at both widths;
   the tests; and `## Owner questions` (pick an option and mark it; don't stop) — at least:
   whether "New admin session" opens Claude or offers Claude/OpenCode (a split button or the
   admin page's own choice).
2. One spec per step, `docs/specs/a2p-<n>-<slug>.md`, from the template. 2–4 steps. Each under
   ~1500 lines and ~90 minutes.
3. `docs/specs/a2p-chain.json`:
   `{"name":"a2p","repo":"../..","base":"a2-steps-6-8","gate":"python3 tools/run_tests.py","retries":2,"steps":[…]}`.
   - `"hard": true` for any step that builds URLs or renders server-supplied strings into the
     DOM (the hand-off link, the session list); `false` otherwise.
   - Every step gets `"scope"`: exactly the files its spec lists under "Files owned", plus its
     test fixtures. `delegate chain PLAN --check` refuses a step whose scope misses one.
   - Write each verify by hand, literally. `set -o pipefail` when it pipes.

## Rules

- Use real names from the code you read. Never invent an API; where step 6's contract is the
  only source, cite the a2a spec section.
- No secrets and nothing from `.env` in a spec.

## Out of scope

Any change outside `docs/specs/`. In the planned slice: the admin page itself (a2a-9), the
launcher and hub APIs (step 6), the hostile container suite (step 8), any new endpoint.

## Acceptance (verify)

`python3 -c "import json,os;p=json.load(open('docs/specs/a2p-chain.json'));assert p['steps'];[open(s['spec']) for s in p['steps']];assert os.path.getsize('docs/specs/a2p-design.md')>3000;print('ok',len(p['steps']),'steps')" && git diff --name-only HEAD | grep -v '^docs/specs/' | (! grep .)`
