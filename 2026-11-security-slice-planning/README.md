# A frontier model and a local model plan the same security-heavy slice

**Result.** Given the same approved design, rules and base commit, a frontier model
(Claude Opus 5.5 (Medium), run as a lead sub-agent) wrote a plan that could run as written. A self-hosted
local model (Qwen 3.8 Flash Next (pennyroyal quantized build, xhigh)) wrote one that
would have failed at its own first gate. Forced through, the local plan would also have shipped a
security hole and an open redirect. Two blind scorers, one from each model family, ranked the
plans the same way: frontier plan 11/14 from both, local plan 2/14 and 5/14. The local plan cost
no frontier tokens and took a third of the time. The local model was also a usable scorer: it
reached the same verdict for free but missed the worst defect.

Placeholders such as `{project}`, `{owner}`, `{hub-host}` and `{opencode-host}` replace names,
hosts and paths.

**The models:**
- **Frontier: Claude Opus 5.5 (Medium)**, in Claude Code, on Anthropic's API. It was the planning lead and the
  frontier scorer.
- **Local (the worker): Qwen 3.8 Flash Next (pennyroyal quantized build, xhigh)**, self-hosted on an OpenAI-compatible endpoint and run by the
  `delegate` harness with OpenCode as the agent. It was the local planner and the local scorer.

The rest of this page calls them "frontier" and "local".

## The project

A self-hosted web hub that puts several coding-agent hosts behind one URL. It has a
security gate, a reverse proxy for HTTP, SSE and WebSocket, a per-host read-only git/files
daemon, and a small installable web app. It runs behind a reverse proxy and a forward-auth
login service.

| Part | Language | Size |
|---|---|---|
| Hub and daemon | Python (standard library only) | 6,850 lines |
| Their tests (unit, socket-level, headless-browser) | Python | 22,750 lines |
| Web app | JavaScript, CSS, HTML (no build step) | 3,330 lines |
| Installers | shell | 2,960 lines |
| Design and planning docs | Markdown | 8,900 lines |
| History | | 61 commits in four days |

## The task

**The slice is "H3: two origins".** It moves the hub's web app from `/hub/` to the root of its own
hostname. OpenCode (the coding-agent web UI) moves to the root of a second hostname. The hub fronts
both, but OpenCode's hostname must also work with the hub removed. It touches the request gate
(Host → role, a stricter Origin rule, body caps per role), the routing table, framing headers
across the two origins, silent sign-in renewal on a second origin, the config format and its
migration, the installer, doctor and docs, and the browser tests.

**The design was written and approved before planning:** [inputs/design.md](inputs/design.md).
It holds the owner's rulings, the URL table per role, the gate changes, the sign-in model, the
config, five high-level steps and the findings of the browser spike already run.

**Both planners had to:**
- turn the design into step specs plus a `delegate chain` plan, each step under ~1,500 lines;
- mark every boundary-guarding step `hard`;
- give every step a verify command with a scope guard;
- state tests as classes plus examples, and "look for the neighbouring cases".

### The planners

- **X. Local model, Qwen 3.8 Flash Next (pennyroyal quantized build, xhigh)**, through the `delegate` harness: one design task, high-effort variant, in an
  isolated worktree. Brief: [inputs/brief-local-planner.md](inputs/brief-local-planner.md),
  which follows the harness's design-brief template.
- **Y. Frontier model, Claude Opus 5.5 (Medium)**, as a `delegate-lead` sub-agent of the orchestrating frontier session. It
  plans every step, writes the specs, then runs the chain. Brief:
  [inputs/brief-frontier-lead.md](inputs/brief-frontier-lead.md).

Both briefs carry the same fixed rules and the same list of neighbour cases. The lead's brief also
asks it to run the chain afterwards; only its plan, committed before the chain started, is
compared here.

### The scoring

- **The rubric was fixed before either plan was read:** [inputs/rubric.md](inputs/rubric.md).
  It has seven criteria, scored 0–2: rulings fidelity, boundary coverage, hard flags and verifies,
  step sizing and order, executability, owner questions, and errors that would ship a bug.
- **The plans were blinded** as X and Y: file prefixes renamed to `plan-`, and one line naming
  the author ("run by the slice lead") reworded.
- **Two scorers got the identical brief** ([inputs/brief-scorer.md](inputs/brief-scorer.md)):
  a fresh Claude Opus 5.5 (Medium) agent, and Qwen 3.8 Flash Next (pennyroyal quantized build, xhigh) as a `delegate` task. Both read
  the real code to check every name a plan used.
- **The orchestrator re-checked the top defects by hand** against the plan files and the design.

## Time and tokens

| | X. Local planner (Qwen 3.8 Flash Next, xhigh) | Y. Frontier lead (Claude Opus 5.5, Medium) |
|---|---|---|
| Wall-clock | 5 min 17 s | ~18 min (planning and starting its chain) |
| Tool calls | 84 | 61 |
| Tokens | 51,046 out (self-hosted, no API cost) | ~219,000 total (frontier API) |
| Output | 5 step specs + design + chain, 746 lines | 6 step specs + chain + a browser-front spike script |

| | Frontier scorer (Claude Opus 5.5, Medium) | Local scorer (Qwen 3.8 Flash Next, xhigh) |
|---|---|---|
| Wall-clock | 4 min 20 s | 7 min 29 s |
| Tool calls | 21 | 67 |
| Tokens | ~141,000 total | 85,932 out (no API cost) |

## Scores (0–2 per criterion, 14 max)

| # | Criterion | Opus scorer X / Y | Qwen scorer X / Y |
|---|---|---|---|
| 1 | Rulings fidelity | 0 / 2 | 1 / 2 |
| 2 | Boundary coverage | 1 / 2 | 1 / 2 |
| 3 | Hard flags + verifies | 1 / 2 | 1 / 1 |
| 4 | Step sizing + order | 0 / 1 | 1 / 2 |
| 5 | Executability | 0 / 2 | 1 / 2 |
| 6 | Owner questions | 0 / 1 | 0 / 1 |
| 7 | Errors | 0 / 1 | 0 / 1 |
| | **Total** | **2 / 11** | **5 / 11** |

## What the scorers found

**Both scorers, independently.** The two marked ✓ were re-checked by hand against the plan and
design files.
- **The local plan's step 1 cannot pass its own verify.** It refuses the old config while
  forbidding edits to the installer that still writes it. It also removes the session picker's
  same-origin route while the UI is out of scope.
- ✓ **Open redirect in the local plan:** `/hub//evil.example` would answer
  `308 Location: //evil.example`. The frontier plan names exactly this case and answers 404.
- **The local plan inverts the sign-in renewal design.** It would need OpenCode itself modified,
  it posts to the wrong origin, and its failure link points at a route that doesn't exist.
- **The local plan's verifies let a skipped browser test run pass,** and its scope guards
  (`^hub/`) are too wide to catch drift.
- **The frontier plan is runnable:** every name it cites exists, its scope guards are per-file
  with negative checks, and its verifies reject skipped browser runs. Its weak points:
  - step 2 knowingly leaves the UI red until step 3;
  - two steps are large;
  - port handling in the same-origin check (the scorers describe it in opposite directions).

**Only the frontier scorer.**
- ✓ **The local plan's hub origin relays every `/h/<host>/oc/…` path,** OpenCode's HTML included.
  The design allows only the API there. Agent-written pages would run on the hub's origin, which
  defeats the point of the slice. This was the worst defect in either plan, and the local scorer
  missed it.

**Coverage beyond the brief's list of neighbour cases:** about 8 in the local plan against 40+ in
the frontier plan (config shapes, Host and Origin spellings, path look-alikes, cap boundaries,
framing headers on refusals, forged `postMessage`, third-origin framing).

**What the local plan did better:**
- a clearer two-hostname browser test stack;
- path-traversal and `Sec-Fetch-Site: cross-site` cases;
- an explicit "never add a skip" rule;
- keeping a non-443 port in the same-origin check.

## Conclusions

1. **On a security-heavy slice, the frontier planner earned its cost.** The local plan failed
   exactly where earlier reviews found the local model's implementation bugs: the case next to the
   named one. Here it happened at plan level, before any code. In
   [2026-11-spec-writers](../2026-11-spec-writers/) the local model's gap was project knowledge it
   could not see. Here both planners had the same rulings in the repo, so knowledge does not
   explain the gap. On a slice whose whole content is boundary cases, the gap is in reasoning
   about the neighbours.
2. **The local model is a useful second reviewer, not a sufficient security reviewer.** It reached
   the same verdict and the same top defects at no API cost. It showed no visible preference for
   its own plan, scoring it lowest. But it missed the one defect that mattered most.
3. **The local planner is ~3.4× faster and costs no frontier tokens.** This test doesn't show where
   that wins; [NEXT-TEST.md](NEXT-TEST.md) proposes how to find the line.

**Limits:** one slice, one run per planner and per scorer. The scorers agree on the ranking, not on
every score. The plans reference a private codebase, so a reader can check them against the design
but not against the code.

## Files

- `inputs/`: the design, both planner briefs, the rubric, the scorer brief.
- `plans/X-local-model/`: the local plan, unedited apart from placeholders.
- `plans/Y-frontier-lead/`: the frontier plan, unedited apart from placeholders.
- `scores/frontier-scorer.md`, `scores/local-model-scorer.md`: both blind scoring reports.
- [results.csv](results.csv)
- [REPEAT.md](REPEAT.md): how to run this with your own models.
- [NEXT-TEST.md](NEXT-TEST.md): the proposed next experiment.
- [tools/blind.sh](tools/blind.sh): the blinding step.
