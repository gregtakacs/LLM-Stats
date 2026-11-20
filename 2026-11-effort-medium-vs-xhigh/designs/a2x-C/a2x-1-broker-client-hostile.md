# a2x-1 — broker and client hostile suite (in-process)

## Goal

Write `broker/tests/test_a2x_broker_hostile.py` covering design §5's cases AX-B1..B15, AX-F1..F10,
AX-G1..G6, AX-C1..C6 against the real `BrokerServer` on a real unix socket, add the shared fake
executable helper `broker/tests/fakebin.py`, and apply the one component fix the sweep is expected
to need: control/BiDi string refusal in `protocol._strings` (design AX-B7, §11 pick).

## Read first

`docs/specs/a2x-design.md` in full (§4, §5, §9, §11 binding); `broker/tests/util.py` (the `Fixture`
and the sh-farm idiom the new module imitates); `broker/protocol.py` (`DETAIL`, `validate`,
`_strings` 400-411, `MAX_LINE`); `broker/server.py` (`_Conn.serve`, `admit`, refuse path 138-147,
`_run_safely` 355-373); `broker/client.py` (exit codes at 45-46); `broker/paths.py:120-162`;
`broker/repocheck.py:32-36, 73, 153-155, 187`; `broker/delegate_rules.py` (flag table, `MAX_ARG_LEN`);
`broker/git_push.py:303-316, 380-396`; `docs/specs/a2-2a-broker-core.md` (wire shapes);
`docs/specs/a2-groups-contract.md` §4.1; `docs/specs/a2g-4-hostile.md` (style: real sockets, per-
case docstrings citing the contract line); `docs/specs/a2a-10-hostile.md` (style for marker sweeps).

## Files owned

- `broker/tests/test_a2x_broker_hostile.py` (new)
- `broker/tests/fakebin.py` (new — patterned on util.py's farm, standalone, imports nothing from
  tests other than stdlib; used by steps 3 and 4 too, so it must not import broker internals beyond
  nothing at all)
- `broker/protocol.py` (fix only: the `_strings` body; no new DETAIL codes, no signature change)

## Contract

- Every refusal case asserts the exact line `{"ok": false, "error": CODE, "detail": DETAIL[CODE]}`
  plus `arg` only where `answer_error` documents it; side effects asserted absent via the fake's
  binlog (zero invocations, or the exact argv cited per case).
- `_strings` fix, precisely: keep NUL, `MAX_STRING`, and surrogate rules; **add** — refuse any
  character whose `unicodedata.category` is `Cc` unless it is in `"\t\n\r"`, and any of
  U+200E, U+200F, U+202A–U+202E, U+2066–U+2069. Still raises `Refusal("bad_request")` unchanged.
  The fix must keep `broker/tests/test_protocol.py` and `test_server.py` green — if one of their
  fixtures carries such a char, that fixture is wrong and gets updated *only if* its docstring
  doesn't promise the char is legal (judgment call; report it).
- `fakebin.py`: `FakeBin(dir)` context manager → `.install(name, *actions, forward=False)`,
  `.argvs()` (list of recorded `{"argv", "cwd", "env"}` dicts in order); actions `exit N`,
  `stdout TEXT`, `sleep S`, `mk PATH`, `tee PATH`; a `forward=True` execs the real git binary found
  at module import (`shutil.which("git")`) after recording. Recorder is one JSONL `binlog` under
  the dir; PATH prepend, never other env mutation.
- The sweep runs twice, modes per design §9 (explicit HOME/XDG + umask 002; cleared + umask 022),
  with the dual run expressed as a decorator so each test method reports as two id-tagged cases.
- Concurrency case AX-B14: 50 threads racing connect+`status`; assert the union of outcomes is
  exactly {one-line answers ≤ 8 overlapping, silent closes}, the binlog shows no interleaved
  partial writes (each recorded invocation's JSON parses), and a final `status` answers `ok` —
  server alive.
- AX-F4's TOCTOU cases drive `paths.read_inside` directly at both seams (resolve→open, open→read)
  as the function's docstring orders it, *in addition to* the view-level swap-between-check-and-
  spawn case; expected refusal names follow `docs/specs/a2-4b-project-groups.md`'s view contract.

## Behaviour and edge cases

Covered by design §5's tables verbatim — implement one test method per AX id, docstring citing the
design row and the code line; group ordering free. The half-written-request case must shrink the
server's `request_deadline` knob rather than sleep on defaults. AX-G* marker files live under the
test tmp dir and are asserted absent after every call *and* after a second `status` (cache path).

## Acceptance criteria

- `python3 tools/run_tests.py` fully green both suites; `ok broker.tests.test_a2x_broker_hostile`
  present.
- Existing broker/launcher/hub suites unchanged green (the `_strings` fix is the only component
  delta; `git show` proves it).
- Scope guard: diff touches only the three owned files.

## Out of scope

Anything hub-, oc-, or live-side; the client's own unit tests (extended only by AX-B15's fake-
broker case); no changes to `util.py`.

## Notes

Free ports; `HOME` never the real one; run the module under `tools/run_tests.py` while working, the
full gate once at the end (delegate-rules §7a).
