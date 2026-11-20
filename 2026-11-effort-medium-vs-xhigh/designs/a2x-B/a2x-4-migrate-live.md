# A2X step 4 — hostile migration, and the live script with its units

**Build**: `oc/tests/test_a2x_migrate.py`, the live script `tools/a2-hostile-live.py`, and
its gate units `tools/tests/test_a2_hostile_live.py`. Two fix targets are named below
(`oc/migrate.py`, `oc/sessions.py`), each behind a case that has to fail first — no case
here expects an edit, and none gets one without a red line.

## Read first

- `docs/specs/a2x-design.md` §6 (the script: its rules, probes L1–L14, the unit contract)
  and §7 (M1–M6, with citations).
- `docs/specs/a2i-5-migrate.md` (the CLI's contract as written, and the report's vocabulary)
  and `docs/specs/a2i-2-image.md` (the container the probes stand inside); the output
  contract to copy is `hub/tests/livecheck.sh`'s — one `PASS`/`FAIL` line per probe, a
  summary line, non-zero on any fail, and every seam an override so a unit test can replay
  the whole thing (`LIVECHECK_*` env names there); the shim pattern to copy is
  `hub/tests/test_h1_acceptance.py`:217–264 (`write_shim`, `SHIM_LOG`).
- `docs/handoff.md` §4 step 1 (every TASK.md carries "one live check") and §5–§6 (what the
  review looks at; the scripts table). This script is the slice's live check and is **not**
  a gate test; only its units are (they never need docker).
- `oc/migrate.py` — `MAX_SOURCE_BYTES` :40 (100 KiB — the real cap; cite the number),
  `MAX_PAYLOAD_BYTES` :43, `REASONS` :51–53, `Usage`/`Failure`/`refuse`/`fail` :68–76,
  `PATH_FLAGS`/`--registry` :119, `Docker.started_by_us` :206 and the wake/stop discipline
  :293–302, the export size/reason path :576–584, `_export_doc` :631–644,
  `default_report_path` :650–654, `write_report` :657–681 (umask-077, `mkstemp`, 0600,
  `os.replace`), and the seams `run_main(argv, run=…, env=…, host_isdir=…)` :692–709.
  `oc/sessions.py` — the import's stdin shape checks :328–337 and the `mkstemp`/`fchmod`/
  `fdopen`/`finally`-`unlink` write :339–348.
- `oc/migrate.py` — `MAX_SOURCE_BYTES` :40 (100 KiB — the real cap, cited in every M1
  assertion), `MAX_PAYLOAD_BYTES` :43, `REASONS` :51–53, `Usage`/`Failure`/`refuse`/`fail`
  :68–76 and `main` :795–808, `default_report_path` :650–654, `write_report` :657–681 (the
  umask-077 + mkstemp + 0600 + `os.replace` sequence and the docstring's reason),
  the export-size path :576–584, the run seam `run_main(..., run=…, host_isdir=…)` :826–
  835. `oc/sessions.py` — the import's stdin checks :328–337 and the `mkstemp`/`fchmod`
  write :339–348.
- `oc/tests/test_migrate.py` — the fixture shape to reuse (a registry, a fake docker via
  the injected `run`), and the suite this one deliberately does not repeat.
- `oc/tests/test_migrate.py` — the fixture shape to reuse (a registry in a temp root, a
  fake `run` object that answers `exec` verbatim), and the suite this one does not repeat.
- `oc/tests/test_install.py` — how a `docker` shim goes on `PATH` for the installer's
  dispatch half, and `oc/projects.py`'s `load_registry` (:808–915) whose refusals the
  migration shares through the same loader.

## Files owned

- `oc/tests/test_a2x_migrate.py`, `tools/tests/test_a2_hostile_live.py` — the suites.
- `tools/a2-hostile-live.py` — the script (new; stdlib-only; executable bit set).
- `tools/tests/__init__.py` — untouched; if the `tools` package needs a marker for the
  runner's discovery, add only what `tools/tests/test_run_tests_tmp.py` already relies on.
- `oc/migrate.py` — only behind a failing M-case, and only the lines that case names
  (the likely target is a CLI-level claim for M5: `O_CREAT|O_EXCL` in the data root, 0600,
  released in the same `finally`, refused through `Failure`'s path at :68–76 — **not** a
  new `REASONS` entry, which is a published vocabulary).
- `oc/sessions.py` — only behind a failing M4 (a follow, or a mode wider than 0600).
- `docs/specs/a2x-design.md` — a corrected cell.

## Behaviour and edge cases — the migration (`oc/tests/test_a2x_migrate.py`)

Everything drives `migrate.run_main(argv, run=fake, env=env)` — the injected `run` is the
docker seam (:692), so there is no executable to fake here and no container to talk to; the
fake records every argv it was handed and answers from a per-call table. The registry and
trees are built on temp dirs the way `test_migrate.py` does it.

- M1, the caps. Do not generate 64 MiB: patch the module constant down (`MAX_PAYLOAD_BYTES`
  = 1024, restored in `tearDown`) and have the fake answer an export of 1025 bytes — the
  reason is `too_large` (:583–584), the run moves to the next session, and the fake's log
  shows no `start`/`stop` caused by the refused file. The source cap is the same trick on
  the other side: a fake checkout whose `oc/sessions.py` is `MAX_SOURCE_BYTES`+1 bytes is
  `fail()`'s path (:105–108) → the `Failure` exit, with the message naming both numbers —
  assert the whole line, since it is the operator's only clue. Then the parse-hostile
  family: stdout of `not json`, of `{"info": {}}`, of valid JSON with 400 levels of
  bracket nesting, and of a well-formed doc whose `info.id` differs from the requested id:
  each is `_export_doc` → `None` (:631–644) → the reason `export_failed`, and the run's
  stdout and stderr carry **no traceback** — asserted as `assertNotIn("Traceback", out)`,
  which is the half a shape assertion misses.
- M2, the report. `--report` into a dir that is a symlink: `write_report` creates its tmp in
  `dirname` (:657–681), so the case asserts where the bytes actually land and that the mode
  is 0600 there — if writing through a linked parent is wrong, the fix is refusing it and
  this step says so in the report rather than asserting the link is fine. `--report` naming
  an existing file: `os.replace` overwrites — pin that (it is the documented choice, the
  tmp+rename exists so a reader never sees half a report), and pin that the overwrite keeps
  0600, not the previous file's mode. A hostile umask (`os.umask(0o077)` inverted: the test
  runs with 0o002 — this host's own trap, `handoff.md` §9) still lands 0600 because
  `mkstemp` is 0600 by definition and `fchmod` says so twice. The default path's parent is
  the data root (:650–654) and the case asserts the two-runs-in-one-second name collision
  behaves (same timestamp → the second replaces the first: pin it, and note it in the
  report as M5's reason to exist). Finally the report's own content: assert the json has
  ids, directories and counters and no field carrying a password or a session body — the
  module says as much at :13–15; the assertion is what turns the sentence back on the code.
- M3, poison inside the data. A source session whose `directory` is `/`, `~`, the *other*
  project's tree, or `<data_root>/../../etc`; whose id contains a NUL, a newline, `..`, or
  a Unicode look-alike of a legal id. The importer treats them as data: the reason is the
  module's own (parent/`directory_missing`/`not_selected`/`verify_failed` — pin which per
  input, with the line cited in the docstring), the registry file is byte-identical
  afterwards, and the fake's log contains no `create`/`run`/`cp` argv naming any of those
  paths. The point of the row is that a poisoned field is inert, so the assertions are all
  "nothing happened" assertions.
- M4, the import's temp file (`oc/sessions.py`, driven directly, no docker): pre-create
  `/tmp/{project}-session-import.json` — the predictable name an attacker would plant — as a
  symlink to `$HOME/landmine`, run the import, and assert `landmine` is byte-identical and
  the tmp path the CLI was given is not that name (`mkstemp`'s random suffix, :339). Then
  the mode half: the fake `oc` helper stats its own argument file and reports the mode in
  the answer — assert 0600 at the moment of the read, not after the `finally` (:348) has
  removed it. A pre-created file at the mkstemp name is the third case: `mkstemp` raises
  and the import fails **without** falling back to a predictable path (assert the exception
  path's `_Fail` message and that no second attempt happens).
- M5, two runs, one shared container. Two threads (not processes — the runner's rule about
  detached jobs) calling `run_main` with the same env and the same fake, whose `start`/
  `stop`/`exec` handlers record timestamps and interleave on a `threading.Barrier`. The
  assertions: both reports exist, are distinct paths, are 0600, and the sets of carried ids
  do not overlap twice with conflicting verdicts; every `start` the fake saw is matched by a
  `stop` from the *same* run (`started_by_us` :206 is the discipline being proven, and the
  fake counts per-caller). If the interleaving shows one run stopping the container under
  the other's in-flight import — a `stop` while the other's `exec` is open — the fix is the
  claim file described in Files owned, and the test then asserts the loser exits with
  `Failure`'s code and an untouched container. Report which outcome the code gave; do not
  ship the test as `skipIf`.
- M6, the hostile argument set: `--from` naming a container that is not in the registry
  (refused: `no_container`, :532 marks the whole plan), `--registry` pointing at a symlink,
  at a 0644 file, at a directory, at nothing (:820/:824/:826's texts arrive as the CLI's
  refusal — the same loader the planner uses, and the case says so), a `--report` inside a
  project's mount (allowed by the code — assert it is allowed *and* that the path appears in
  no fake argv: the container must never be told where the operator's report lives), and a
  `--project` value that repeats, that is empty, and that names the *other* fixture's
  project. Each with the exit code `main` gives (:795–808) and the fake's log empty for
  every refusal.

## Behaviour and edge cases — the live script (`tools/a2-hostile-live.py`)

The script is the slice's live check (handoff §4 step 1) and runs at cutover, on the host,
as the owner. Its contract is `hub/tests/livecheck.sh`'s shape, in Python:

- **Invocation**: `--project A --other B` both required, `--registry PATH` (default the
  real one), `--docker NAME` (the executable name it will call, default `docker`),
  `--container-prefix NAME` (default `projects.py`'s `CONTAINER_PREFIX`, :38), `--egress`
  (enables L13), `--user UID:GID` (default `1000:1000`, `oc/Dockerfile:116`), `--dry-run`.
  Refusals come **before** any subprocess: missing/unknown names, a name absent from the
  registry file, `docker` not on `PATH` → a one-line usage/`ERROR` message, exit 2, no
  traceback.
- **Every seam is injectable** so the units can replay it: the docker executable, the
  registry path, the two project names, the user, and the probe list itself (`--only L1,L4`).
  The script runs docker as argv lists through one `run()` helper — no shell string
  interpolation anywhere, which is what makes unit (f) below provable.
- **Read-only, absolutely**: no `stop`/`rm`/`pull`/`create`/`start`, no `run`, no `cp`, no
  broker verb but `doctor`/`list`, no host writes. A probe that must write (there is none
  required) would write in the container's own `/tmp` and remove it in the same argv.
- **Output**: one line per probe — `PASS <id>`, `FAIL <id> <one line of what was seen>`,
  `SKIP <id> <why>` — then `LIVE: <n> probes, <m> failed`. Exit 0 when `failed == 0`
  (skips included, each saying why), 1 on any FAIL, 2 on a refused invocation.
- **Probes, all fourteen, one function each**: L1 uid/gid, L2 `/proc/1`, L3 the socket's
  mode and writability, L4 the other project's tree and the state root, L5 the environment
  and `/proc/1/cmdline`, L6 the copied dotfiles, L7 the read-only root, L8 the AF_UNIX
  connect, L9 `{project}-broker doctor` and its `--repo` shape, L10 the proxy variables and the
  allow-listed host, L11 name resolution and the other container's port, L12 link-local,
  host-side and off-egress direct, L13 the egress container's CA key (with `--egress`), L14
  `/etc/hosts`' pins. Each function's docstring names the threat it proves
  (`a2-design.md` §10's row, or the contract section it pins). The trio that must never regress: L1 (attacker is 1000:1000),
  L8 (the socket answers EACCES/EPERM or nothing at all — a refusal that leaks the peer's
  own uid back is a FAIL), L12 (link-local, host-side and off-egress direct all fail within
  5 s — the `--internal` network is the wall this proves).

**The units (`tools/tests/test_a2_hostile_live.py`)** — a `docker` shim on `PATH`
(`test_h1_acceptance.py`:249's pattern: a script dir, an executable, `SHIM_LOG`-style
record of every argv, canned stdout/stderr per probe from a fixture the test writes), the
script invoked as `python3 tools/a2-hostile-live.py …` with `HOME`/`XDG_*` in a temp root:

- (a) all-PASS transcript → exit 0, one line per enabled probe in probe order, and the
  summary `LIVE: 14 probes, 0 failed` (the count is what catches a probe silently dropping
  out of the list).
- (b) a mutated transcript where one must-be-denied read returns content → that exact
  `FAIL <id>` line, exit 1, the summary counts one — the control for (a), and the case that
  proves the script is not just printing PASS.
- (c) no `docker` on `PATH` → exit 2, the message, empty call log (the script never guessed
  a path).
- (d) `--dry-run` → the docker argv it would run, one per line, exit 0, call log shows no
  exec ran.
- (e) missing `--other`, an unknown `--project`, a registry file that does not exist, a
  registry whose names are not the two given → each exit 2 with an empty call log.
- (f) every exec argv contains `--user 1000:1000` (or the flag's value) and the container
  is `CONTAINER_PREFIX + name` as **separate argv elements** — asserted from the shim's
  per-element log, which is also the assertion that no project name reaches a shell string.
- (g) a probe whose canned answer is a hang marker → the script's own timeout fires, the
  probe FAILs with the timeout in its line, and the run continues to the next probe (one
  dead container cannot swallow the check).

## Acceptance criteria

- `python3 tools/run_tests.py oc.tests.test_a2x_migrate tools.tests.test_a2_hostile_live`
  exits 0; the chain's verify shows both `^ok` lines inside a full green gate run
  (`python3 tools/run_tests.py` — this step is `hard`).
- The M-rows that stayed green say so in the report; any fix made in `oc/migrate.py` or
  `oc/sessions.py` names the case that forced it, and both `oc` suites pass with it.
- `oc/tests/test_migrate.py` and `hub/tests/test_h1_acceptance.py` pass unchanged — the
  first is this file's neighbour, the second is the shim pattern being imitated, and a
  break in either means the imitation drifted.
- The script runs clean against a fake: `python3 tools/a2-hostile-live.py --project alpha
  --other beta --registry <temp fixture> --docker <shim> --dry-run` exits 0 and prints the
  L1–L14 command set (that exact invocation is in the report, with its output).
- Scope guard: `git diff --name-only <base>` touches only Files owned.

## Out of scope

The broker (steps 1–2), the planner and the relay (step 3), the coverage table and the
handoff findings (step 5). The container image's own conformance (A2I-2's suite) and the
egress container's CA/key unit claim (A2I-4's — L13 is that claim's live twin, not its
test). Running the script against real containers is the owner's cutover action; nothing in
this step may require a live docker daemon, and the units must pass on a machine with none.
