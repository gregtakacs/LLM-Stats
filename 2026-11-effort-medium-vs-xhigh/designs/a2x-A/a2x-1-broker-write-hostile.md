# a2x-1 — broker write-path hostile (gate layer)

## Goal

Close the six broker gaps named in `docs/specs/a2x-design.md` §"Step 1" with one new hostile
module, `broker/tests/test_a2x_write_hostile.py`, in the style of `test_groups_hostile.py` /
`test_a2a_hostile.py`: every case asserts the documented refusal **and** the absent side effect
through the recording fakes. Where a case finds a real hole (case 2 is expected to), fix the
component in the same commit.

## Read first

- `docs/specs/a2x-design.md` (ground rules, the gap list, owner Q1/Q4)
- `docs/specs/a2-design.md` §10 (threat rows), ruling 26
- `docs/specs/a2-broker-contract.md` §5 (codes + sentences), §6.6 (targets from config), §6.7
  (child env)
- `broker/tests/test_groups_hostile.py` (fixture + subprocess-client style to copy),
  `broker/tests/util.py` (`Fixture`, `Peer`, `call_log`, `git_calls`), `broker/tests/fakes/`
- `broker/paths.py` (`resolve_arg`, `read_inside`, `select_target`), `broker/protocol.py`
  (`DETAIL`, `Refusal.arg_echo`, the caps), `broker/server.py` (`MAX_CONNECTIONS` = 8, deadline),
  `broker/client.py` (exit codes 125/69, the stderr line format), `broker/git_push.py`
  (`own_gitdir`, `scan_project_config`, `FORCED_CONFIG`), `broker/runner.py` (`GIT_ENV` line ~182
  — note: it pins `GIT_CONFIG_NOSYSTEM=1` but **not** `GIT_CONFIG_GLOBAL`: case 4 probes the
  user-global leak), `broker/tasks.py`/`broker/plans.py` (the delegate push chain inside
  `delegate`)

## Files owned

- `broker/tests/test_a2x_write_hostile.py` (new)
- fix scope (only if a case proves a hole): `broker/paths.py`, `broker/server.py`,
  `broker/protocol.py`, `broker/client.py`, `broker/audit.py`, `broker/git_push.py`,
  `broker/runner.py`
- `broker/tests/util.py` — helpers may be **added**, none changed or removed
- `broker/tests/fakes/git` — its REPORT env list may be **extended** (additive only) if it does
  not yet record `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_NOSYSTEM`/`GIT_CONFIG_SYSTEM`

## Contract

No new public surface. Every expectation cites existing code:

| case | expected shape (verbatim from code) | side effect proven absent |
| --- | --- | --- |
| live-client `--repo B` from A's socket | client exit 125; stderr exactly `broker: that repository is not a member of this project. (unknown_repo)` (`protocol.DETAIL["unknown_repo"]`, `client.py` format) | `fx.git_calls()` has no `push`; no `fetch` either |
| smuggled `targets` key | one-line `bad_request` answer, `protocol.DETAIL["bad_request"]` | no child started (`fx.call_log()`) |
| hard link into B | `not_a_file` from `paths.read_inside` after the nlink fix (`paths.py:185` refuses non-regular names; the gap is a regular file with `st_nlink > 1`, whose name sits inside A but whose inode is B's — `real()` never sees it) | B's bytes appear in no answer frame |
| `.git` swap mid-push (target) | `unsafe_config` (`DETAIL` verbatim) | `fx.git_calls()` records no push for that target |
| four hard config flags via delegate | `unsafe_config`, one case per flag (`subTest`) | fake git call log has no `push` |
| `filter.*`/`diff.external` | read op **accepted** (not the four HARD flags of `repocheck.py`) | — (positive case) |
| host-side git env | fake git's recorded env has `GIT_CONFIG_NOSYSTEM=1` (`runner.GIT_ENV`, pinned today) and its recorded argv carries the `FORCED_CONFIG` `-c` masks; probe: any host-executing config key that slips past both (user-global `include.path` shape) → fix by adding `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` `/dev/null` pins to `GIT_ENV`; `PATH` in that env without `$HOME` | — (env/argv assertion) |
| bidi/10k arg | a 10 000-char arg is *valid* (under `MAX_STRING` 65536): the case pins it round-trips to the fake delegate whole, one answer, and the refusal *echo* path truncates to 200 (`protocol.MAX_ARG`, `Refusal.arg_echo`); bidi/zero-width chars travel as opaque data — pin they survive framing unchanged and reach the audit only truncated-as-echoed | audit copy holds no untruncated payload; framing stays one line |
| ref `main\n` | `bad_request` (parse) — push `ref` regex `^…$` with `re.MULTILINE` off; pin which code, and fake git records nothing | no push |
| half-write then close | connection dies; next request on the same socket answers normally | no `delegate` entry in `call_log()` |
| 50 concurrent | every connection: exactly one answer line (`ok`/`busy`) or a clean EOF; ≥42 of the 50 answered (`server.py` backlog+cap 8 semantics: at most 8 accepted concurrently, the rest `busy` or refused at accept — pin observed split as a range, the invariant is *one answer or clean close*, no hangs); process alive | children started ≤ 8 at any instant (fake delegate records overlap window) |
| 1-bad-in-50 batch | request #17 gets its one refusal line; the other 49 get valid answers | the bad request started no child |

## Behaviour and edge cases

1. **Live-client cases.** Reuse `test_groups_hostile.py`'s subprocess pattern
   (`[sys.executable, str(CLIENT), ...]` with `env=` carrying the socket path and a
   **spoofed** `PROJECT_TARGETS=B=<B repo path>` and `PROJECT_PROJECT=B`) to prove the peer's
   environment is decoration: answers come from the broker's config for the socket it listens on
   (contract §6.6). Case `--repo B` from A's socket (A's config has no member named `B`).
2. **Hard link (expected to find a hole).** In a fixture, `os.link` a file inside B's repo into
   A's worktree on the same filesystem; `paths.read_inside` must refuse it. Today it does not:
   lstat says regular file, `real()` stays inside A (a hard link is only a name), and the read
   follows the shared inode into B's bytes. Fix in `broker/paths.py`: right after the
   `S_ISREG` check, refuse `known.st_nlink > 1` with `not_a_file` — the same code a symlink gets,
   because the complaint is the same: *the name does not exclusively name one plain file inside*
   (`paths.py:185` comment is the precedent). Apply the same rule to the `stat` op's path if it
   shares the check; keep every existing refusal and code untouched. A directory-nlink refusal
   already exists in spirit via the parent rules — do not regress it.
3. **`.git` swap mid-push.** For a collab target via `--repo`: start the delegate push chain
   against the fixture whose recorder blocks between config-check and push (the fake git sleeps
   when `FAKE_GIT_SLEEP` is set — add that knob to `broker/tests/fakes/git` **only if** the
   existing fakes lack a blocking hook; check first, `test_delegate_write.py` already has a swap
   mechanism to copy). Swap `.git` to an outside dir; answer must be `unsafe_config`; fake git log
   shows the check calls but no push.
4. **Host-side git env through the fake.** The fake git records `env` (it already strips
   secrets — read it to see the record format first); assert the pins in case 4's table row.
5. **Concurrency tests** use threads + the real `Peer`/socket, never mocks. 50 connections:
   collect (answer-line-or-EOF) per connection; assert the invariant, not an exact split.
6. All fixtures set `HOME`/`XDG_*` to their tmpdir and explicit dir modes (0700/0600), host umask
   is 002.

## Acceptance criteria

- `python3 tools/run_tests.py broker.tests.test_a2x_write_hostile` → `ok`; then the module runs
  green inside the full gate.
- If a hole was found (case 2 expected): the fix commit contains both the test and the component
  change; full suites green; `test_paths.py`, `test_server.py`, `test_delegate_write.py`,
  `test_push.py`, `test_groups_hostile.py` all still green — no existing test changed.
- Scope guard: only Files owned touched.

## Out of scope

Anything about `oc/`, `hub/`, `launcher/`, `tools/`; no new codes or sentences; no changes to
`fakes/*` unless the step-3 blocking knob above is needed (justify in the commit body); no live
docker (ruling 26 — this layer is in-process by design).

## Notes for the worker

Run only your module while iterating (`tools/run_tests.py broker.tests.test_a2x_write_hostile`);
full suites once at the end. Commit test+fix together. Report `STATUS: blocked` only if a case
needs a decision the design's Owner questions don't answer.
