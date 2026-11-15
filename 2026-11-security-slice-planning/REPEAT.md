# Repeating this with your own models

The protocol needs a real project, a frontier model, a local model, and a harness that can hand a
written brief to each. The one used here, `delegate`, is open source: it runs an agent (OpenCode)
on any OpenAI-compatible endpoint, in an isolated git worktree. Any pair of agents that can read a
repo and write files will do.

## 1. Pick the slice

- Choose a change in your own project that touches a **security boundary**: auth, request
  validation, routing, tokens, sandboxing, cross-origin rules. It should be big enough to split
  into 4–6 steps.
- **Write and approve its design first.** The planners plan from a design; they don't write one.
  Put every owner ruling that binds the slice into the design file. Rulings left only in someone's
  notes measure knowledge, not planning (see `../2026-11-spec-writers/`).
- Record the base commit. Both planners start from it.

## 2. Brief both planners identically

- Start from `inputs/brief-local-planner.md` and `inputs/brief-frontier-lead.md`. Replace the
  paths, section numbers and file names with your project's. Keep the structure:
  - the read-first list;
  - the fixed requirements;
  - what to write;
  - out of scope;
  - an acceptance check.
- **The fixed requirements must be word-for-word the same in both briefs,** including the list of
  named neighbour cases. Criterion 2 counts the cases each plan adds *beyond* that list.
- Give the planners different file prefixes (here `h3w-` and `h3-`) so their outputs can't collide.
- Run them in parallel from the same commit. Record wall-clock, tool calls and tokens.
  - Frontier: the harness's usage counter.
  - Local: `delegate report`'s `time`, `tool calls` and `output tokens` lines.

## 3. Fix the rubric before reading either plan

- Use `inputs/rubric.md` as-is or adapt it. Write it down and timestamp it before you open either
  plan's output.

## 4. Blind the plans

```bash
tools/blind.sh <planX_dir> <prefixX> <planY_dir> <prefixY> <out_dir>
```

- It copies each plan to `out_dir/X` and `out_dir/Y` with file prefixes renamed to `plan-`.
- It lists every line that might reveal an author (model names, "lead", "worker", "local model",
  harness names) for you to reword by hand.
- **Decide privately which plan is X.** Keep the key out of the scorers' reach.

## 5. Score with two scorers, one per model family

- Give both the same brief (adapt `inputs/brief-scorer.md`), with read access to the blinded plans,
  the rubric and the real codebase. They must check every name a plan cites against the code.
- **Expect each scorer to favour the plan its own family wrote,** and read the scores with that in
  mind. Here the local scorer still scored its own family's plan lowest.

## 6. Verify the scorers

- Re-check the top 2–3 defects each scorer reports against the files yourself. A scorer's mistakes
  come back in the same confident tone as its findings.
- Note the defects only one scorer found. That gap is a result in itself (criterion: reviewer
  recall).

## 7. Report

Copy `README.md`'s shape:
- the result first;
- the project and the task;
- time and tokens;
- the score table from both scorers;
- the findings, with the hand-checked ones marked;
- conclusions and limits.

Keep the plans unedited apart from placeholders.

## Placeholders used here

`{project}` the project, `{owner}` its owner, `{hub-host}` / `{opencode-host}` the two
hostnames, `{repo}` the checkout path, `{infra-repo}` the owner's infrastructure repo,
`{frontier-model}` / `{local-model-high}` the models, `{blind-dir}` the scorers' input folder.
