# Design-slice comparison: rubric (fixed 2026-11-20, before any design was read)

Two design tasks from {project}'s A2 work, each run four times from the same brief and base commit
(`4c607321a8`): `a2p` (the unified picker, A2 step 7) and `a2x` (the hostile-container suite, A2
step 8). Each run wrote a design doc, one spec per step and a chain plan under `docs/specs/`.
The four runs per task are blinded as A–D. Score every run 0–2 per criterion, with evidence
(file:line). Score a whole task's four runs side by side, one criterion at a time.

1. **Rulings fidelity**: the owner rulings in the A2 design (§8, "Owner questions — answered", the
   step-4 / step-5→6 / step-7–8 rulings, e.g. ruling 24's two-button bar and on-demand list, 25,
   26's two-layer hostile suite) and the brief's fixed rules are reflected correctly; nothing
   contradicts them.
2. **Boundary coverage**: the security-relevant checks are concrete, testable statements. For a2x:
   the hostile cases (another project, the broker socket, a secret, a host path, `--repo`/path
   tricks) and their neighbours. For a2p: the admin hand-off (top-level link, never a cross-origin
   POST, nothing starts before Open), disabled states, project isolation of the session list.
   Count neighbour cases beyond the brief's own list.
3. **Hard flags and verifies**: boundary steps `hard`; each verify runs the right suites (including
   every test module the step adds or edits) and a scope guard against the previous step's branch;
   a browser-test skip treated as failure.
4. **Step sizing and order**: each step plausibly < ~1500 lines / ~90 min of worker time;
   dependencies in the right order.
5. **Executability**: real file/function names in the repo at the base commit (no invented APIs);
   spec paths resolve; chain JSON valid for delegate (`name`, `repo`, `base`, `steps[].name/spec/
   verify/hard`); scope lists neither too narrow nor too wide.
6. **Owner questions**: real gaps the design left open, not re-asking settled rulings.
7. **Errors**: anything that would ship a bug or a security hole if followed literally.

Also give each run a one-line overall verdict ("would accept as is" / "accept after small fixes" /
"needs a rewrite"), and rank the four runs per task.

Limits: two tasks, two runs per model each; only one design per task was ever executed (the
accepted one, not among these), so these are judged on paper.
