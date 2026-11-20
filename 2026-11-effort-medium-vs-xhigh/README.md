# Does xhigh reasoning effort pay off on hard work? (medium vs xhigh, same local model)

**Short answer: no, not on these tasks.** On one hard implementation task and two hard design
tasks, a self-hosted Qwen 3.8 Flash Next (pennyroyal quantized build, on an RTX 6000 PRO) at
**medium** reasoning effort matched itself at **xhigh** on every quality measure we had, while xhigh
took longer and spent more tokens. The bigger effect was something else: **two runs of the same
model at the same effort differed far more than the two efforts did.**

## The question

The owner's delegate harness runs the local model at two effort levels: medium for ordinary steps,
xhigh ("hard") for steps that guard a security boundary or carry real algorithmic difficulty.
History suggested xhigh bought little (same pass rate, ~1.7× the tokens), but history is biased:
xhigh only ever got the hardest steps. The owner never runs xhigh on easy work, so the only question
that matters is: **on hard work, is xhigh worth it?**

## Method

Three past slices were replayed exactly: same brief, same base commit, same verify command pinned to
that commit (a moving branch name would skew the scope check), no verify re-run on failure.

| Task | Kind | Why it is hard | Runs |
|---|---|---|---|
| `b3-fix` | implementation | a real concurrency race in a Go dial gate ({orb-project} `tools/{orb-tool}`); the original test failed ~2 in 10 runs | 3 medium, 3 xhigh |
| `a2p-design` | design | a unified session picker with a cross-origin admin hand-off | 2 medium, 2 xhigh |
| `a2x-design` | design | a hostile-container test suite: cross-project, socket, secret and path attacks | 2 medium, 2 xhigh |

Quality was measured beyond "the verify passed":

- **b3-fix:** each fix ran the race test **1,000 times with Go's race detector on 4 CPUs**. Control:
  the unfixed base commit fails the same stress (4 failures in 1,000), so the stress does detect
  the bug.
- **Designs:** the eight designs were blinded (A–D per task, mapping kept from the scorer) and
  scored by a fresh Claude Opus 5.5 agent on a seven-criterion rubric fixed before any design was
  read ([inputs/rubric.md](inputs/rubric.md)). The scorer checked every named file and function
  against the repo at the base commit. The originally accepted designs were *not* given as a
  reference: they came from an earlier xhigh run plus edits, and would have biased the scoring.

## Results

All 14 runs passed their verify. Per task and effort ([results.csv](results.csv)):

| Task | Effort | Verify | Mean wall | Output tokens | Reasoning tokens | Tool errors | Quality |
|---|---|---|---|---|---|---|---|
| b3-fix | medium | 3/3 | 62 min | 20k | 45k | 2.0 | **0 failures in 3 × 1,000 race runs** |
| b3-fix | xhigh | 3/3 (1 timed out after a passing verify) | 65 min | 21k | 76k | 2.0 | **0 failures in 3 × 1,000 race runs** |
| a2p-design | medium | 2/2 | 22 min | 45k | 62k | 4.5 | blind scores **10**, 5 (of 14) |
| a2p-design | xhigh | 2/2 | 37 min | 76k | 103k | 11.0 | blind scores 9, **2** |
| a2x-design | medium | 2/2 | 44 min | 56k | 35k | 5.0 | blind scores 9, 5 |
| a2x-design | xhigh | 2/2 | 54 min | 75k | 53k | 5.5 | blind scores **10**, 6 |

Design totals over both tasks: **medium 29, xhigh 27** (of 56). Per-design scores, verdicts and
evidence: [scores/blind-scores.md](scores/blind-scores.md); unblinding: [scores/blind-mapping.txt](scores/blind-mapping.txt).

## What it means

1. **xhigh did not buy quality here.** The race fixes were equally correct under stress, and the
   designs scored the same within noise.
2. **xhigh costs more.** Designs took 25–70% longer, with ~1.4–1.7× the output tokens and
   ~1.5–1.7× the reasoning tokens; b3-fix used ~1.7× the reasoning tokens. The one timeout was
   xhigh's.
3. **Run-to-run variance dominates.** The same model at the same effort produced a 10 and a 5
   (medium, a2p), and a 9 and a 2 (xhigh, a2p). Half of all eight designs were judged "needs a
   rewrite" by the scorer, two at each effort.
4. **So the cheaper lever is breadth, not depth.** Two medium designs cost about the same wall time
   as one xhigh design. Picking the better of the two medium designs gave 10 on a2p (both xhigh
   designs scored lower: 9 and 2) and 9 on a2x (xhigh scored 10 and 6). A single xhigh run was as
   likely to land on its bad draw as a single medium run.

## Limits

- Three tasks, two or three runs per effort: enough to see no large xhigh advantage, not enough to
  rule out a small one.
- One scorer, one model family as scorer. The earlier experiments in this repo found scorers from
  different models agreed on rank but not on every defect.
- The designs were judged on paper; none of these eight was executed.
- The b3-fix verify and stress share one test; a different hidden defect would not show.
- Concurrency: up to four runs shared the GPU with other work, which adds noise to wall times
  (equal for both arms by design: runs were interleaved).

## Reproduce

[inputs/run.sh](inputs/run.sh) and [inputs/verifies.sh](inputs/verifies.sh) are the runner and the
pinned verifies; [inputs/](inputs/) holds the briefs and rubric. The designs and the race fixes are
in [designs/](designs/) and [fixes/](fixes/) (with each fix's 1,000-run stress log).
