# A2X step 2 — hostile files: git-config exec, the check→use window, copies, concurrency

**Build**: `broker/tests/test_a2x_gitconfig.py` and `broker/tests/test_a2x_files.py`, one
fake executable, one additive fixture helper, and the two-table fix B17 asks for. This is
the step where the slice may change broker runtime code, and only the named lines of the
named files.

## Read first

- `docs/specs/a2x-design.md` §3 (a hostile case that fails is a bug in the component) and
  §4's rows B16–B31 with their citations.
- `docs/specs/a2-broker-contract.md` §5 (codes), §6.1 (the read path, in order), §6.4
  (`--copy`, 1 MiB), §8 (the audit line), §11 (a refused request leaves no spool).
- `docs/specs/a2g-4-hostile.md` — H18–H20 are these files' neighbours (shared member dir,
  `.git` symlink, hooksPath through the *groups* door): no case here repeats one; the two
  modules' docstrings cross-reference by id.
- `docs/specs/a2-design.md` §10's git-config-exec and symlink rows.
- `broker/repocheck.py` — `DANGEROUS_KEY` :32–35, `HARD` :36, `_HardGit` :39–58 (the
  `-c` overrides + `runner.child_env_git`), `check` :60–113 (the scope discipline via
  `_project_scoped`, `git_push.py:40–50`), `resolve_member` :329–363, `select_target` :370,
  the `--repo` shape rules :401–422.
- `broker/paths.py` — `read_inside` :172–226: `lstat`+`S_ISREG` :185–190, `real`+`inside`
  :191–194, `O_NOFOLLOW` :196, `fstat` re-check :199, the `/proc/self/fd` re-check
  :200–204, the size cap :205/:220 (`too_big`).
- `broker/delegate_rules.py` — `_copy_name` :567, `_spec_file` :588–600 (`resolve_arg`
  before `read_inside`, and why), the spool call at :623.
- `broker/runner.py` — `child_env` (:48, `HOME` moved into the task dir, token patterns
  dropped) and `child_env_git` (the `GIT_CONFIG_*` pair).
- `broker/tests/util.py` — `Fixture(groups=…, state=…)`, `Peer`, `call_log()`; rewriting
  the `delegate` fake's state file *before* connecting is how a child is given hostile
  behaviour deterministically (util.py:170–176).
- `broker/tests/test_paths.py` :215–290 — the existing swapped-fd test, which swaps
  **inside→inside** to pin "the fd is the check"; B20 here swaps inside→outside from a
  child, which that file cannot do.
- `review/d1-git-exec.sh` :44–50 — the orchestrator's git-config exec probe for the
  daemon's git API (the `ext_diff`/`textconv`/`fsmonitor` marker matrix): same class of
  probe, different component; the B16–B19 markers are written so a reader can run that
  script's idea against the broker and get the same answer.
- `review/h2-repo-roots.py` :1–14 — the independent-hostile-script pattern (build a nasty
  tree, run the real thing, print PASS/FAIL totals) that step 5's `review/a2x-hostile.py`
  continues.

## Files owned

- `broker/tests/test_a2x_gitconfig.py`, `broker/tests/test_a2x_files.py` — the suites.
- `broker/repocheck.py` — the `DANGEROUS_KEY` regex (:32–35) and its comment only.
- `broker/delegate_rules.py` — only if B17 shows the verb paths consult a second list
  rather than `repocheck.check`; the change is to *call* the shared table, not to reorder
  anything.
- `broker/paths.py` — only if a case below fails against the read path itself; the expected
  outcome is no edit, and an edit without a failing case is scope creep.
- `broker/tests/fakes/delegate` — additive behaviour only: a state-file mode that swaps a
  named link before exec'ing (the existing log/state conventions keep). A new fake file is
  out of scope; the state mode is enough, and the chain's scope list names only these paths.
- `docs/specs/a2x-design.md` — an "expected" cell the run corrected, and the fix's row.

## Behaviour and edge cases

**`test_a2x_gitconfig.py` (B16–B19).** Every case builds a real repository in the fixture's
member dir and runs a delegate verb at it over the socket. The fake `git` the config names
is the point of measurement: its recorded argv (with its recorded environment) is the
evidence that no host `git` ever saw the hostile config.

- B16, the existing pair re-pinned for the post-groups broker: `core.fsmonitor =
  /tmp/<marker>` and `core.hooksPath = <member>/.git/hooks` set in the repo's local config
  → `answer_error("unsafe_config")` byte-exact (`repocheck.check` raises it with the key as
  `arg`, :96–113), the marker file's absence proven *after* the request, and the fake
  git's recorded environment containing `GIT_CONFIG_GLOBAL=/dev/null` and
  `GIT_CONFIG_NOSYSTEM=1` (`runner.child_env_git`) with the `HARD` pair
  (`-c core.hooksPath=/dev/null -c core.fsmonitor=false`, :36) on every call. A case for
  each of the table's families (`filter.*.process`, `diff.*.textconv`, `include.path`,
  `includeif.*.path`, `core.sshCommand`, `core.gitProxy`, `core.worktree`) — the table is
  one regex, and one case per family is what keeps a future edit from losing an arm.
- B17, the gap and its fix: the four keys `credential.helper`, `diff.external`,
  `remote.origin.pushurl`, `url.<base>.insteadOf` set locally. Today none matches
  `DANGEROUS_KEY` (:32–35): `git status` inside the child would run the helper. The step
  extends the table (and `diff\..+\.external` joins the `diff\..+\.(?:command|textconv)`
  arm) and the test asserts, for each key on the delegate path, `unsafe_config` with the
  key as `arg`, and on the push path that the same repo still pushes: `FORCED_CONFIG`
  (`git_push.py:52–60`) neutralises all four and the fake git's recorded argv carries each
  `-c` override. That second half is the fix's cost accounted for: refusal on one path, no
  regression on the other. The push-path case asserts also that the *stripped* answer
  leaves no marker file touched — the neutralisation is real, not hopeful.
- B18, the shapes of a config file that hide a key: the dangerous key written across a line
  continuation (`[core]\n\tfsmonitor = \\\n\t/tmp/x`), written with a unicode escape the
  parser folds, written in a file `include.path` points at *outside* the repo (the
  include itself is refused by scope, `_project_scoped`, and the test pins that `arg`
  names the include key and never the foreign path). Each: `unsafe_config`, or — where
  the parse genuinely cannot see the key — the fail-closed answer the module gives; the
  test pins which and why in its docstring, and a gap that allows execution through is a
  finding for the report, not an xfail.
- B19, the order: the fake `git` records each call's argv; the assertion is that the first
  recorded call of a `run`/`top`/`diff` request is `repocheck.check`'s own
  `config --show-origin -l` (under `HARD`), and that no call *before* the verdict could
  have exec'd anything — i.e. no call other than `rev-parse`/`config` family appears
  earlier than the allow-list's pass. This is the ordering citation of
  `resolve_member`→`check` in `repocheck.py:329–363` turned into a machine check.

**`test_a2x_files.py` (B2, B20–B22, B24–B26, B28, B31).** B23, B27 and B29 are step 1's:
they are grammar cases, and this file's module docstring says so once, so the two files read
as one partition of the B-table.

- B2, the project directory gone between config and request: config written, tree removed,
  one `delegate doctor` → `outside_project` (server.py's answer for a project with no
  directory left, :397–405) with no traceback in the broker's log, and the next connection
  to a recreated config behaves normally (the socket outlives one project's death).
- B20, the swap from the child's side: the fixture's `delegate` fake is given (by its state
  file, written before the request) the behaviour "before printing anything, repoint
  `task/<id>/spec.md`'s symlink from the in-project file to `<outside>/marker` and exec the
  real read". The request is `run` with a spec whose name the child may touch, and the
  assertion is on what the *broker* then reads for the resume/continuation path:
  `read_inside` refuses (`not_a_file` for a symlink at :190, `outside_project` for the
  swapped path at :193, or the `/proc/self/fd` "swapped under us" `outside_project` at
  :204, according to where in the order the swap lands), and in no case does a frame
  contain `marker`'s content. The three codes are one expectation here — the *window* is
  what is tested, the exact arm that catches it is recorded in the test docstring from the
  run.
- B21, the same race with the roles reversed: the link starts outside and is swapped in.
  `not_a_file`/`outside_project` — nothing is read that the check did not see, and the
  audit line names no member (the refusal is pre-target, `PRE_TARGET_CODES` server.py:610).
- B22, the FIFO: a FIFO at the spec path inside the project → `not_a_file` (S_ISREG first,
  :185–190), **never a hang** — the test bounds itself with `Peer`'s socket timeout and
  asserts elapsed < 2 s, which is the assertion the missing `O_NONBLOCK` would fail; a
  Unix socket and a directory at the same path answer the same code (one test, three
  shapes).
- B24, the copy sizes: three small `--copy` files plus one over the 1 MiB read cap →
  `too_big` (`read_inside` :205/:220), nothing spooled (the spool directory is empty after
  — the §11 rule; `util.py`'s spool helpers check it), and the response carries no byte of
  the oversize file. The counter-case: the same four where the big one is 1 MiB−1 →
  accepted, four copies in the fake's log; a copy file that *grows* between `lstat` and
  the size cap is the B20 discipline in another dress and the fake does it the same way.
- B25, `--copy` grammar: `".."`, `"a/b"`, `""`, `"~"`, a name over 128 characters, a name
  with a newline (the same bytes with `/` and without), `.` → `bad_argv` with the value as
  `arg` (`_copy_name` :567, `COPY_RE` :64), and — the half a substring assertion would
  miss — the byte after the refusal is the end of the connection, no frame of any kind
  follows.
- B26, the protocol-level refusals that must not leak through a copy path: `--copy` naming
  a file that is a symlink to outside, and one whose parent is a symlink out: the two
  answers are `outside_project` (resolve_arg, :597 before read_inside :599 — the ordering
  the docstring at :588–600 exists to state).
- B28, the resource edges: `Fixture(max_running=2)` (util.py's knob) and six threads each
  running one `run` to completion, plus five malformed connections interleaved → every
  connection gets exactly one verdict line; the `busy` refusals are
  `answer_error("busy", op=…, sub=…)`-shaped (server.py:542) and their audit lines parse
  **alone** — the append-only-line discipline, asserted by reading the log and requiring
  every line to be one complete record; the fake delegate's log never shows three
  simultaneous children; the five malformed ones get their framing codes and nothing else.
- B31, the two-member no-cwd no-repo case: config with two collab members, a request with
  neither `cwd` nor `repo` → `no_repo`, DETAIL cited verbatim (protocol.py:59–61 — a
  sentence that names no repository is the point), and the audit line has no `member=`
  field at all (`_delegate_target` returns None, server.py:613–640).

## Out of scope

The wire framing and grammar edges (B1–B15): step 1. The planner, the relay, the live
script, migration: steps 3–4. Any `oc/*` or `hub/*` file. The group-boundary cases
a2g-4 owns, and the sibling boundary probe `review/h2-repo-roots.py` runs for the daemon —
if a case here and that probe's idea disagree, report it.

## Acceptance criteria

- `python3 tools/run_tests.py broker.tests.test_a2x_gitconfig broker.tests.test_a2x_files`
  exits 0, and the full gate green in the chain's verify (the `^ok` greps for both
  modules).
- The B17 fix: both suites green, and `python3 tools/run_tests.py broker` green — the push
  suite is the regression fence the fix is not allowed to break; the commit's message names
  the four keys.
- Scope guard: `git diff --name-only <base>` touches only Files owned.
- The report states, per failing-then-fixed case, what the code did before the fix (the
  finding) and the command that shows it fixed — a2x-5 puts those lines in the handoff.
