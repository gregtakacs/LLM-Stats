# Score two H3 plans, blind, against a fixed rubric

Read-only review. Write exactly one file: `docs/specs/h3-plan-score.md` (your report). Change
nothing else; write no code.

## Context

{project} is a Python stdlib hub (gate + reverse proxy + static UI); this checkout is its base
state for the slice. The slice ("H3") moves the hub's UI to the root of its own origin and serves
OpenCode at the root of a second origin. The approved design is `docs/h3-design.md` (binding: §2
rulings, §10 owner rulings, §8 steps and spike findings). Other context the plans cite:
`AGENTS.md`, `docs/handoff.md` §4–§7, `docs/h1-design.md` §2 D3, §4, §6.1, §6.6, §7.1, §8.3,
§11.1, `docs/h2-design.md` (renewal), earlier specs `docs/specs/h2-*.md`, `docs/specs/h2c-*` and
their chain JSONs (the format the delegate tool runs), the code under `hub/` and `hub/tests/`.

Both planners got the same design, the same fixed rules, and the same base. Their outputs
(mounted read-only):
- Plan X: `{blind-dir}/X/`
- Plan Y: `{blind-dir}/Y/`

File prefixes were renamed to `plan-` in both; the chain JSON spec paths refer to the original
names, so judge path resolution by structure, not by the renamed file names. A base branch name
may read `BASE`.

## Task

Rubric: `{blind-dir}/rubric.md`
(same mount). Score each criterion 0–2 for each plan, every score with evidence (file:line in the
plan, and the code file:line you checked it against). Check claims against the real code: do the
named functions, constants, tests and files exist (for example `hub/proxy.py` `route_for`,
`hub/gate.py` `body_cap`, `ROOT_SW_BODY`, `BrowserStack`)? Would each verify command actually work
with `tools/run_tests.py` and the scope-guard pattern AGENTS.md describes? For criterion 2, list
the neighbour cases each plan specifies beyond the ones the design and the shared brief named (the
brief named: wrong-role paths; Host case/port/trailing dot; a hostname in both roles; sibling
origin as Origin; `Origin: null`; missing Origin on a WebSocket upgrade; `/hubx`, `/%68ub/`,
`//hub/`; `/h/_hub/` on the hub origin; `/sw.js` relayed only on the OpenCode origin; body caps
row by row).

Criterion 7 matters most: anything that, followed literally, would ship a bug or security hole,
or make a chain step fail (for example a step that breaks the shipped UI mid-chain, a scope list
missing a file the step must edit, a verify that passes on a skipped browser run). Be concrete.

Do not guess who wrote which plan, and don't let length or polish stand in for correctness: a
shorter plan that is right beats a longer one that is wrong.

## Report (`docs/specs/h3-plan-score.md`, under ~900 words)

A table criterion × {X, Y} with scores; per criterion 1–3 lines of evidence; a list of concrete
defects per plan, ranked by severity; anything one plan has that the other should borrow; and a
one-paragraph verdict on whether either plan could run as-is.
