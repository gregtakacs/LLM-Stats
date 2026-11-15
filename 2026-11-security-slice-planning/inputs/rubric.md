# H3 plan comparison: rubric (fixed 2026-11-14, before either plan was read)

Plans: A = delegate-lead ({frontier-model}), B = local worker (`h3w`, {local-model-high}). Same design doc,
same fixed rules, same base commit 1f19283.

Score each 0–2, with evidence (spec file:line). Same scorer for both; read B's first where
possible.

1. **Rulings fidelity**: R-H3-1..3 and §10 rulings 1–4 each reflected correctly; nothing
   contradicting the design (e.g. keeps single-origin mode, keeps the sw.js replacement on the
   OpenCode origin, real domain names).
2. **Boundary coverage**: the gate checks as concrete, testable statements: role from Host,
   Origin = own origin, one routing/cap table, 308 `/hub…`, `/h/_hub/`, framing header, renewal on
   the OpenCode origin. Count the listed neighbour cases the specs carry *beyond* the brief's list
   (that is the handoff §5 failure: only the named cases).
3. **Hard flags and verifies**: every boundary step `hard`; verify commands run the right suites
   and a scope guard against the *previous step's* branch; browser-test skip treated as failure.
4. **Step sizing and order**: each step plausibly < ~1500 lines / ~90 min; dependencies right
   (e.g. two-hostname BrowserStack introduced in the first step that needs it; UI move not before
   the routes it calls).
5. **Executability**: real file/function names (no invented APIs), spec paths resolve, chain JSON
   valid in delegate's format, the scope lists cover the files each step must touch (too narrow
   fails the step; too wide hides drift).
6. **Owner questions**: real gaps the design left open, not re-asking settled rulings.
7. **Errors**: anything that would ship a bug or a security hole if followed literally.

Also record: wall time, which model, and {frontier-model} cost (A: the lead's tokens; B: only my brief +
review time).

Limits of the comparison: one slice, one run each; only A's plan is executed, so B is judged on
paper (plus: would its chain have passed?). Don't generalise past "on a security-heavy slice".
