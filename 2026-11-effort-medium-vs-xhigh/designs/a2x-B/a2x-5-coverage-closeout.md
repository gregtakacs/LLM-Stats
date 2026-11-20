# A2X step 5 — the coverage table filled in, the slice's hostile probe script, the findings

**Build**: `review/a2x-hostile.py`, the completed §2 coverage table in
`docs/specs/a2x-design.md`, additive probe rows in the live script and its units where
steps 1–4 proved one missing, and the slice's findings recorded in `docs/handoff.md` §6 and
§9. **No runtime file changes in this step** — the last four steps owned the code; this one
owns the accounting, and a gap it cannot close with a test becomes a numbered line in the
handoff, not an edit made at the deadline.

## Read first

- `docs/specs/a2x-design.md` §2 (the table as written *before* the suites existed — every
  row's "covered by" cell is what this step replaces with the truth), §3 (the rules the
  suites had to obey, so the check is "did they", not "did they say"), §6 (the live
  script's probe list), §8 (the step list), §9 (the three owner questions this step must
  answer in prose wherever the run settled one).
- The four step specs (`a2x-1` … `a2x-4`) — each ends with the report its worker owed, and
  those four reports are this step's input. Read them in the evidence dir first; anything
  a report claims and the tree does not show is a finding to write up, not to fix quietly.
- The suites as they now exist: `broker/tests/test_a2x_hostile.py`,
  `broker/tests/test_a2x_gitconfig.py`, `broker/tests/test_a2x_files.py`,
  `oc/tests/test_a2x_planner.py`, `hub/tests/test_a2x_relay.py`,
  `oc/tests/test_a2x_migrate.py`, `tools/tests/test_a2_hostile_live.py` — the ids each
  actually contains, taken from `grep -n 'def test_'`, never from the design's table.
- `docs/handoff.md` §6 (the review-script table: what a row says), §9 (Loose ends: what a
  line there says — one bullet, the symptom, where the fix belongs), §5 (what the local
  model misses — the reason a coverage table exists at all).
- `review/h3_hostile.py` :1–20 (the shape to continue: unittest classes run against a real
  server started on a scratch port, with `if __name__ == "__main__"` at the end) and
  `review/h2-repo-roots.py` :1–14 (the older shape: a bare script, a nasty tree in a temp
  dir, `PASS`/`FAIL` lines, a total). `a2x-hostile.py` is the first shape, because the
  broker and the hub both have in-process harnesses now.
- `tools/run_tests.py` (the gate this step must run whole, twice, and report honestly about
  even when it is green on the first try).

## Files owned

- `review/a2x-hostile.py` — new.
- `docs/specs/a2x-design.md` — §2's table, §9's answers, and a row's expectation cell
  where the last four steps proved the citation wrong (each such edit names the test that
  proved it).
- `docs/handoff.md` — one appended row in §6's table, appended bullets in §9. Nothing
  existing in that file is edited or reflowed: the file is the next session's memory and
  rewriting it is how a rule gets lost.
- `tools/a2-hostile-live.py`, `tools/tests/test_a2_hostile_live.py` — **additive only**: a
  new probe id, or a new unit asserting a probe that steps 1–4 found unproven. No probe's
  expected answer changes here; if one must, that is a step-4 finding and goes to §9 with
  the reason.
- The seven test modules — docstring and comment fixes only (the id-mapping lines, the
  cross-references between `a2g-4`'s H-rows and these B-rows). **No assertion in any test
  file is changed, removed or added in this step**: assertions belong to the step that owns
  the case; this one's job is to prove the set is complete, and an edit here would be the
  same test writing its own report card.

## Contract — the coverage table

§2's table has one row per threat in `a2-design.md` §10 and `a2a-design.md` §11. For every
row, the cell becomes: the test function name(s) that prove it, or `live L<n>` for the
host-script half, or `— not covered: <one-line reason and where the fix belongs>`. Three
rules for filling it:

1. A name must be grep-able: take it from `grep -n 'def test_'` of the module as it exists
   on this branch. A cell that names a test nobody wrote is worse than an honest dash —
   that is how a threat row gets *considered* covered and never tested, which is handoff §5
  's whole subject.
2. A threat with two layers gets both cells (the gate case *and* the live probe), because
   the in-process fake proves the code and the live probe proves the deployment: the socket
   mode (L3), the bind list (L4), the environment (L5), and the network wall (L10–L12) are
   each *two* rows of evidence, not one.
3. A dash is allowed only where a component, not a test, owns the row (B30's same-uid peer;
   a second OS user per project is A3 material). Each dash must name the component.

Then the table gets the reverse check written as a comment at its foot: the list of test
ids that *do not* map to a threat row (B/K/R/L/M ids with no §10/§11 parent — there will be
a few; they are the slice's additions, and the reader should see them listed rather than
wondering where they came from).

## Contract — `review/a2x-hostile.py`

Standalone, stdlib, `python3 review/a2x-hostile.py [CHECKOUT]`, exit non-zero on any FAIL,
`PASS n FAIL n` total line, and a `--list` flag that prints the case ids and exits 0 without
starting anything — so the step's verify can prove the script exists and enumerates its cases
without depending on a live port in a container that may not have one. What makes it worth a file rather than a grep: it runs the
**cross-cutting sequences** no per-module suite owns, against the real components with the
fakes only where the suite spec says fakes are legal (docker/git/gh):

- `S1 install → two projects → broker`: drive `oc/install.sh projects create` twice with the
  recording `docker` fake, take the two configs it wrote, and ask the *real* broker, over
  its own socket, for the other project's tree (`outside_project`), the other project's
  member (`unknown_repo`, byte-equal to nonsense), and a plain `doctor` for each project.
  The point is the handoff between the two components: the layout the planner chose is the
  layout the broker enforces, and nothing today tests them together.
- `S2 relay → broker`: with two live `FakeOpenCode`-backed projects at the hub, ask
  project A's page surface for a session id that only project B's registry holds, then ask
  the broker for the same cross-project thing, and assert both refusals carry no path and
  that neither component's audit/log line names the project that was *not* asked for.
- `S3 the migration's wake discipline under a hostile export`: a `run_main` run whose export
  answers garbage for one session, and one whose import dies mid-way (`host_isdir` seam),
  asserting the shared container was stopped exactly once and the report's counters agree
  with the report's lists (the arithmetic, which M-cases each check one piece of).
- `S4 the umask trap`: every directory and file the two-project install created — the
  registry, the layout dirs, the broker socket dir, the report — stat'd in one loop, with
  the expected mode named per path; this is the case the *host* broke before
  (`handoff.md` §9's umask-002 entry) and the reason the review script exists beside the
  gate.
- `S5 the fixed shapes at once`: for every refusal this slice's suites pin, the script
  prints the actual line — a run with `--print-shapes` that produces a text file the
  reviewer diff-checks against the four step specs' cited shapes. It is a documentation
  test in a country where documentation tests do not exist, and it is the cheapest way to
  catch the failure mode this whole slice is aimed at: a code change that silently moves an
  error string out from under a spec.

Ports: bound at 0 and read back (the runner's rule — never one of the review scripts'
7795–7818 numbers, which the handoff reserves and which collide under the parallel runner);
temp roots via `tempfile`, `HOME`/`XDG_*` pointed into them.

## Contract — the findings in `docs/handoff.md`

- §6's table gains one row: `review/a2x-hostile.py`, what it covers in the table's own
  idiom, and its known false FAILs — which must be `none` or an honest named list, never
  blank.
- §9 gains one bullet per open item, each in the file's voice: what was seen, the command
  that shows it, and where the fix belongs. The minimum set this step must write up (with
  whatever the run actually found, which may add to it):
  - **B17**: the four git-config keys, the fix made in step 2, and the push path's answer
    after it — one bullet, because a reader of `repocheck.py` will wonder why the table is
    what it is.
  - **K4**: the planner accepts a reserved project name; the broker config and the hub route
    table refuse it; the bullet says which of the three should own the check, and that the
    test that pins today's disagreement is `oc/tests/test_a2x_planner.py`'s K4 case.
  - **K7**: which address classes `pin_hosts` now refuses and which it deliberately does not
    (site-local stays legal — the LAN model host is a real deployment), so the next reader
    does not "finish" the fix.
  - **Q-X3 / B30**: same-uid peercred, pinned as an accepted boundary; the bullet says the
    container half is L8's and the OS-user half is A3's if the owner wants it.
  - every M5-class finding step 4 reported (a lifecycle claim made or not made), and every
    cell of §2's table that ended in a dash.
- And one line saying what the slice **did not** do, if anything: a probe that needs a live
  daemon and could not be unit-tested, a case left to a later slice. §9 is where an honest
  gap lives; a gap that exists only in a worker's report is a gap that disappears.

## Contract — the gate

This step is the last of the chain and it is `hard` for a reason: it is the only point where
the five suites, the A2H relay suite, the A2I migration suite and the installer dispatch
suite have all been changed at once. `python3 tools/run_tests.py` (both suites, whole) must
exit 0 on the squash, twice, run detached (`setsid -f`) with the output in the evidence dir
per the repo's rule; then `review/a2x-hostile.py` green. A flake found here is written into
§9 with its reproduction, not retried away — and note `handoff.md` §9's known flake
(`daemon.tests.test_log_endpoint`) so the second run's difference is not blamed on this
slice's work.

## Acceptance criteria

- `python3 tools/run_tests.py` exits 0 (the whole gate, both suites), with the log in
  `$DELEGATE_EVIDENCE_DIR`; `python3 review/a2x-hostile.py .` exits 0 and its FAIL count is
  0 in its own total line.
- §2's table: no cell empty, every named test greps to a definition in the module named
  (the step's report includes the grep loop that proves it, one line per row), every dash
  names a component.
- The live script's probe count in its units' all-PASS assertion equals the table's L-rows
  (a probe added in step 4 that the units' count does not know about is exactly what the
  assertion catches — this criterion is that assertion, restated).
- `docs/handoff.md`: the diff is appended lines in two sections and nothing else
  (`git diff docs/handoff.md` must show no changed existing line); `docs/specs/a2x-design.md`'s
  diff shows the filled cells.
- Scope guard: `git diff --name-only <step-4 branch>` touches only Files owned.
- The report: the table's before/after in three sentences, the findings list, the two full
  runs' output tails, and `STATUS:`-shaped honesty about anything that did not close.

## Out of scope

Every `broker/*.py`, `oc/*.py`, `hub/*.py`, `launcher/*.py`, and any assertion in any test
file (Files owned says why). The live script's **run** against real containers — that is the
owner's cutover action, and this step's contribution to it is the script, the units, and the
handoff line that tells the owner what to expect to see SKIP. Pushing, deploying, and
squash-merging: the orchestrator's, and the repo's rule says ask first.
