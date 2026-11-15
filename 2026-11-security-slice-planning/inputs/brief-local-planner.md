# H3 design: plan the slice and write its step specs (no product code)

## Goal

Slice **H3** of {project}, designed in `docs/h3-design.md` (approved by the owner; §8 lists the
steps at a high level, §10 the owner rulings). Your job in this task is **design only**: the
slice design, a spec per step, and a `delegate chain` plan that other workers will run step by
step. Write no product code. Use the file prefix **`h3w`** for everything you write (another
plan uses `h3`; do not read or write `docs/specs/h3-*`).

## Read first

- `docs/h3-design.md` in full: §2 rulings R-H3-1..3 and §10 owner rulings are binding. Step 0 of
  §8 (the browser spike) is done; its findings are in §8. Plan from step 1.
- `AGENTS.md` (test runner, test policy for delegate chains, scope guard), `docs/handoff.md`
  §4 (routine), §5 (what reviews keep finding), §7 (rules).
- The parts of `docs/h1-design.md` that H3 supersedes or refers to: §2 D3, §4 (the gate), §6.1,
  §6.6, §7.1, §8.3, §11.1. And `docs/h2-design.md` for the renewal mechanism (`renew.html`,
  `auth_frame_origins`).
- The code it changes: `hub/config.py`, `hub/gate.py`, `hub/proxy.py`, `hub/api.py`,
  `hub/__main__.py`, `hub/doctor.py`, `hub/install.sh`, `hub/static/` (all of it), the hub tests
  under `hub/tests/` (notably `test_h2_browser.py`'s `BrowserStack`/`PageSession`,
  `test_routing.py`, `test_request_line.py`, `test_streaming.py`, `test_ui.py`), `docs/hub-install.md`,
  `docs/hub-agent-install.md`.
- How earlier slices were planned, which you should imitate: `docs/specs/h2-*.md`,
  `docs/specs/h2-chain.json`, `docs/specs/h2c-*.md`, `docs/specs/h2c-chain.json`.
- The step-spec template: `{skills-dir}/delegate/spec-template.md` (mounted read-only).

## Fixed requirements

- Each step is one coherent change, under ~1500 diff lines and ~90 minutes of worker time.
  Keep §8's order; keep boundary steps separate from UI/docs steps.
- `"hard": true` on every step that touches the gate, routing, Origin checks, body caps, config
  validation, framing headers or the renewal, and on the last step.
- Verify commands: light steps (static/UI path move, installer/docs) run their own test modules
  through `python3 tools/run_tests.py <modules>` plus the scope guard; hard steps and the last
  step run `python3 tools/run_tests.py` (both suites, in full) plus the scope guard. Every verify
  ends with a scope guard: `git diff --name-only <the previous step's branch>` (the chain base
  `h2` only for step 1) must list only files in the step's declared scope. Browser tests must not
  be skipped in a verify (a skipped run is a reject, as in h2/h2c).
- Specs state test classes plus examples and tell the worker to look beyond the list for the
  neighbouring cases (handoff §5). Cases the specs must cover at least: wrong-role paths; Host
  case, port and trailing dot; a hostname in both roles; the sibling origin as `Origin`;
  `Origin: null`; a missing Origin on a WebSocket upgrade; `/hub` prefix tricks (`/hubx`,
  `/%68ub/`, `//hub/`); `/h/_hub/` on the hub origin; `/sw.js` relayed only on the OpenCode
  origin; the body-cap table row by row on both roles, with one table used by both routing and
  caps. Every fix that could be bypassed needs a test that fails on the base commit.
- Generic (R-H3-3): no real domain, network or provider names in code, tests, docs or specs (use
  `hub.example.com` / `code.example.com`); no secrets.
- UI: the slice changes paths only, no new look. The UI step follows the repo's UI verification
  rule: screenshots at 390×800 and 1440×900, light and dark, every PNG read.
- New tests use free ports (`bind(("127.0.0.1", 0))`). The browser test stack will need to serve
  two hostnames; plan that in the step that first needs it.

## What to write

1. `docs/specs/h3w-design.md`: what the slice adds, mapped to h3-design's sentences (cite §);
   config and migration; routes per role with their gate rules; the gate as concrete checks; what
   waits for later slices; and `## Owner questions` (pick an option and mark it; don't stop).
2. One spec per step, `docs/specs/h3w-<n>-<slug>.md`, following the template. 2–6 steps.
3. `docs/specs/h3w-chain.json`:
   `{"name":"h3w","repo":"../..","base":"h2","retries":2,"steps":[…]}` (same shape as
   `h2c-chain.json`).

## Rules

- Respect the rulings, and use real names from the code you read. Never invent an API.
- No secrets and nothing from `.env` in a spec.

## Out of scope

Any change outside `docs/specs/h3w-*`.

## Acceptance (verify)

See the task's verify command: the chain parses, every spec it names exists, the design file is
over 3000 bytes, and nothing outside `docs/specs/h3w-*` changed.
