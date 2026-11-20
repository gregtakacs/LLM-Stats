# a2x-1 — Broker hostile suite: cross-project and transport, through the socket

**Goal.** Prove A2's central claim at the broker seam: a session that holds *A's* broker socket
can make A's broker do A's work and nothing else — every attempt to name, reach, or leak another
project's or the host's resources answers with the contract's refusal, runs nothing, and says
nothing it should not. This is design `docs/specs/a2x-design.md` §5.1 (cases XB1–XB18); the
suite is the delta over the per-module broker suites, which already fight each component alone.

**Read first.** `docs/handoff.md` (the slice routine); `docs/specs/a2x-design.md` §1–§5 (§4 names
the fakes you reuse, §5.1 is your case table, §8 your fix scope); `docs/specs/a2g-4-hostile.md`
(the hostile-suite style: one test per attack, the shape checks you copy — one-line answer,
fixed detail, arg names no path, all fake logs empty, the foreign id absent from the audit);
`docs/specs/a2a-10-hostile.md` (its worker-rules block: umask 002, XDG into temp, never the real
home); then the code under attack: `broker/protocol.py`, `broker/server.py`, `broker/paths.py`,
`broker/repocheck.py`, `broker/delegate_rules.py`, `broker/git_push.py`, `broker/services.py`,
`broker/client.py`, and the fixture you reuse, `broker/tests/util.py` — read `PROJECTS`,
`Fixture`, `Peer`, `delegate_request`, `push_project_config`, `enable_service`, and
`test_targets.GROUPS` before writing a line.

**Files owned.** `broker/tests/test_a2x_broker_hostile.py` — the only file you create.
**Fix scope** (only if a case finds a real defect, narrowest change that satisfies the existing
contract): `broker/*.py`. Record any fix in the commit message like the FINDING precedent in
`oc/tests/test_acceptance.py`; if the fix would change an error code or refusal *shape*, do not
fix — report it as blocked with the reproduction.

## Contract table (the expectations you assert — cited, not invented)

| Fact | Source |
|---|---|
| a refusal is one line `{"ok": false, "error": …, "detail": …[, "arg": …]}`; `arg` cut at `MAX_ARG`=200; fixed sentences live in `protocol.DETAIL`; the project named is the socket's, never the request's | `protocol.answer_error` (`protocol.py:423`), `protocol.MAX_ARG` (`protocol.py:24`) |
| `unknown_task` is silent-as-absence: a foreign id and a never-heard id answer byte-identically | `tasks.require_task` (`tasks.py:183`), `test_targets` precedent |
| cross-project repo member = `unknown_repo`; absolute-path-shaped `repo` never reaches the resolver (compare resolved paths) | `broker/paths.py:134`, `delegate_rules.py:195` |
| cwd outside → `outside_project`; read of a link/dir/fifo → `not_a_file`; swap-after-open → refused via fd recheck | `paths.child_cwd` (`paths.py:104`), `paths.read_inside` (`paths.py:172`) |
| steering keys (`core.worktree`, `include.path`, `includeIf.*`, `core.fsmonitor`, `core.hooksPath`, `filter.*`, `diff.*.command/.textconv`, `core.sshCommand`, `core.gitProxy`) in project-writable config → `unsafe_config` (`repocheck.DANGEROUS_KEY`, `repocheck.py:31-34`); `credential.helper` is not a *refusal* — the push pipeline forces it empty and mounts only its own helper (`git_push.py:40,115-118`) | `broker/repocheck.py`, `broker/git_push.py` |
| the push pipeline forces its own `-c` config, in order (`FORCED_CONFIG` incl. `core.sshCommand=ssh`), with the runner's env only | `git_push.py:34-38` and its env construction |
| frame caps: line `MAX_LINE`=262144 (newline inclusive), string `MAX_STRING`=65536, argv 1–`MAX_ARGV`=64, arg ≤ 200; `parse_line` refuses NUL, non-finite numbers, dup keys, bytes after the newline | `protocol.py:21-24`, `parse_line` (`protocol.py:205`), `validate` (`protocol.py:285`) |
| one request per connection; over-long line → `too_large` without reading the rest; the connection dies after the answer | `server.handle_one_request`, the `too_large` refuse (`server.py:582`), `request_deadline` (`server.py:60`) |
| connection cap: the extra connections are accepted and answered `busy`; over `max_running` in-flight → `busy` refusal, one line, client exit 125 | `server.MAX_CONNECTIONS` (`server.py:32`), `test_server`/`test_delegate_write`/`test_push` precedents |
| service argv: broker-minted names only; `FORBIDDEN_FLAGS`/`FORBIDDEN_WORDS` refuse publish, mounts, host/net=none paths | `services.check_argv` (`services.py:116`), (`services.py:64-66`) |
| the client is a subprocess: 125 refusal / 69 unreachable / child's code / 137 killed; the socket is `PROJECT_BROKER_SOCK` (`ENV_SOCKET`) | `client.py:28,46-47` |

## Behaviour and edge cases (your test list = design §5.1 XB1–XB18)

Group the module in classes mirroring the table: `CrossProjectIdentity` (XB1–XB5, XB18),
`ConfigSteering` (XB6, XB17), `PathWalk` (XB7, XB8), `TransportPoison` (XB9, XB11–XB13),
`PushSurface` (XB14, XB15), `ServiceSurface` (XB16), `Concurrency` (XB10). Every test drives the
**real broker over the real socket** (`Fixture.start()`, `Peer`), with the existing PATH fakes;
the canary values of design §5 make "never named B" a substring assertion. XB4 is the control
that keeps the suite honest: the same request that is `unknown_repo` on A's socket must **run**
on B's. Where a case needs git's config steering planted in a repo, use the `util.git` helper on
the fixture's real repos. Concurrency: burst 50 connects on one socket (expect the `busy`
protocol answer, no traceback, socket healthy afterwards) and assert in-flight `busy` at the
fixture's own `max_running` the way `test_delegate_write` does.

## Acceptance criteria

1. `python3 tools/run_tests.py broker.tests.test_a2x_broker_hostile` passes; every design §5.1
   case is a named test method whose name cites its XB id in the docstring.
2. The full gate passes (`python3 tools/run_tests.py`) — including the anonymity gate: no site
   values in the new file.
3. Scope guard: `git diff --name-only <base>` lists only the owned file (plus, if and only if a
   defect forced a fix, files under `broker/` matching the fix scope, each named in the commit
   message).
4. The module's tests use free ports only, set `HOME`/`XDG_*` into their temp dirs, and never
   write to the real home.

## Out of scope

No hub or oc file. No new fakes. No changes to `broker/tests/util.py` (if a helper is missing,
build it privately in your module). No contract changes — report, don't rewrite.

## Notes (worker rules)

No git history commands (the harness commits each round). Host facts that bite: umask 002 —
assert modes explicitly; `git` exists, `docker`/`gh`/`delegate`/systemd do not, so every case
runs through the PATH fakes as the broker's own suites do; `/tmp/opencode` may be unwritable —
use `$DELEGATE_EVIDENCE_DIR`. Run long suites detached with `setsid -f`, never a background job
that ignores SIGINT. While working, run only this module through `tools/run_tests.py`; the full
gate once, at the end. Your verify (from `a2x-chain.json`) is the check the orchestrator trusts;
do not substitute a narrower one.
