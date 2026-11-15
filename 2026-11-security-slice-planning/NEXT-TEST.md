# Where is the line? Proposed next tests

## What we know so far

The line between "delegate to the local model" and "keep with the frontier model" is not one
line. It depends on two things: **what kind of change** it is, and **which phase** of the work.
The evidence so far, all from one owner's real projects:

| Phase | Light work (UI, docs, installers) | Ordinary features with tests | Security boundaries |
|---|---|---|---|
| **Design / plan** | untested | close second, when given the owner's rulings ([2026-11-spec-writers](../2026-11-spec-writers/)) | **fails** (this test: 2–5/14 vs 11/14) |
| **Implement** (from a frontier plan) | most steps accepted first round | most steps accepted first round | works, but the bugs that reach review sit in exactly these steps |
| **Review / score** | untested | untested | same verdict as the frontier scorer, but missed the worst defect (this test) |

The blank cells, and the "why" behind the failing one, are what the next tests should fill.

## Test 2 (next, cheapest): can a little frontier work rescue the local plan?

**The question.** Is the local planner's gap something a short frontier artifact can close, or
does the frontier have to write the whole plan? This is the practical form of the line: what is
the *smallest* piece of frontier work that recovers the quality?

**The method.** Same slice, design, base commit, rubric and blinding as this test. Add two arms
and rescore all four plans blind:

| Arm | Planner | Extra input | Frontier cost |
|---|---|---|---|
| X (this test) | local | none | ~0 |
| **X1** | local | a frontier-written **neighbour-case list**: one page, threats and look-alike inputs per boundary in the design, no plan | ~10–20k tokens |
| **X2** | local | none, but a mandatory **second pass**: "list every neighbour of every check in your specs, then add the missing tests" | ~0 |
| Y (this test) | frontier lead | none | ~219k |

**What it tells us.**
- If X1 reaches ~Y, the rule becomes: the frontier writes the threat list, the local model writes
  the specs. That would cut the frontier cost of planning by roughly 90%.
- If X2 reaches ~Y, it's a prompting gap, and the fix belongs in the harness's design template.
- If neither does, security planning stays with the frontier, and the next question is
  implementation only.

**Hold fixed:** the two scorers, the rubric, and the hand verification of the top defects.

**Run each arm three times** to see the run-to-run spread; this test had one run each.

## Test 3: the ladder (execute the plans, count escaped defects)

**The question.** Where on the scale from light work to security boundaries does a local plan,
implemented by the local model, stop being good enough, measured by bugs that reach the end and
not by a rubric?

**The method.** Pick three upcoming slices of the same project, one per class:
- **Light:** UI paths, docs, an installer flag.
- **Ordinary:** a feature with data logic and tests, no boundary.
- **Boundary:** auth, routing or validation (or reuse this slice).

For each slice:
1. Write and approve the design.
2. Plan it twice (local, frontier), as in this test.
3. **Run both chains** with the same local implementer.
4. Review both results with the same fixed review: full suites on a clean squash, a hostile script
   written *before* seeing either result, and a frontier review of the boundary code line by line.
5. Record, per arm: plan score; did the chain pass first time; defects found in review, by severity;
   defects that escaped review and were found later (live use, the next slice); frontier tokens;
   wall time.

**The decision rule.** For each class, delegate planning when the local arm's severe escaped
defects are no higher than the frontier arm's at lower total frontier cost. Count the review
needed to reach parity in that cost.

## Test 4: reviewer recall on planted defects

**The question.** Can the local model do the *review*, and on which kinds of defect does it fail?
This test hinted at the answer: same verdict, but it missed the most serious finding. One data
point is not a rate.

**The method.**
1. Take a merged, reviewed slice.
2. Plant about 15 defects across four tiers:
   - **Named:** the exact case the spec named.
   - **Neighbour:** the case next to a named one, like this test's open redirect.
   - **Cross-component:** a correct part that breaks another part, like this test's hub-origin relay.
   - **Process:** a verify that passes on a skipped test, a scope guard too wide to catch drift.
3. Give the diff to each model as a blind review task.
4. Measure recall and false positives per tier.

**What it tells us.** A local model that catches named and process defects but misses neighbour
and cross-component ones is a cheap first-pass reviewer. The frontier then reviews only those
tiers, which is where the review tokens should go.

## Order and cost

| Test | Effort | Frontier cost |
|---|---|---|
| 2 | about one afternoon; reuses this test's inputs | ~0.5M frontier tokens across three runs |
| 4 | about one day to plant the defects; cheap to run | small |
| 3 | rides along with real work, one slice at a time | the frontier arms are work that has to happen anyway |

Together they turn the table above into a rule per cell.
