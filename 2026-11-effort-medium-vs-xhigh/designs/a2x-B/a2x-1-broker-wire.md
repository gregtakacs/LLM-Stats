# A2X step 1 — hostile wire: the broker socket's framing, grammar, cross-project and resource edges

**Build**: `broker/tests/test_a2x_hostile.py`, plus a fixture helper in
`broker/tests/util.py` and a fake mode under `broker/tests/fakes/` where a case needs one.
The family is the socket's **wire and grammar**: B1–B15 and B23/B27/B29 (the copy count, the
NUL and the undecodable line, the key shapes). The file/exec/copy/concurrency family —
B16–B22, B24–B26, B28, B31 — is step 2's, and the two sets are one partition.
Nothing else in the repo changes: this step pins the broker as it stands on
`a2-steps-6-8`, and every expectation below is cited from that code. If a case fails, the
component is wrong — report it as a finding with its reproduction; the fix belongs to the
step that owns the file (a2x-2 owns `broker/repocheck.py`/`delegate_rules.py`/`paths.py`,
a2x-3 owns `oc/*` and `hub/*`).

## Read first

- `docs/specs/a2x-design.md` — §1 (the two layers), §3 (the rules: cited shapes, three
  assertions per refusal, isolation, no site values), §4's table rows B1–B15.
- `docs/specs/a2-broker-contract.md` §4 (framing and the check order: shape → op → keys →
  values; one connection, one request), §5 (the refusal codes), §8 (the audit line),
  §10 (the client's exit codes).
- `docs/specs/a2a-10-hostile.md`, `docs/specs/a2g-4-hostile.md` — the format to imitate
  and the suites not to duplicate: A2A-10 owns the launcher's raw-socket half, a2g-4 owns
  the groups boundary; B-rows here are the broker socket's own edge, on the *current*
  broker including groups and service.
- `broker/tests/util.py` — `Fixture(groups=…, config=…)` (a full config document, so a
  hostile request can be pointed at a second fixture's project), `Peer` (raw bytes,
  `foreign_uid=`), `call()`, `delegate_request()`, `call_log`, the `docker` fake's state
  and log. Fakes are reached by **config paths**, never by PATH (util.py's module
  docstring: the system `git` would shadow a fakes-dir PATH entry).
- The cited sources of the expectations: `broker/protocol.py` (`DETAIL` :17–95, limits
  :21–28, `COMMON_KEYS` :30, `PUSH_KEYS` :317, `MAX_REPO_NAME` :33, `SESSION_RE` :35,
  `parse_line` :205, `parse_object` :212 with `_lexical_depth` :343/`_no_dupes` :374/
  `_no_constant` :383, `validate` :286–308, `_keys_of` :310, `_argv` :328, `_push` :339,
  `_cwd` :354, `_repo` :366, `_orch` :384, `_strings` :397, `answer_error` :422–437),
  `broker/server.py` (`refuse` :126, `peer_refused` :149, `_read_line` :561–591,
  `busy` :325/:542, `PRE_TARGET_CODES` :610), `broker/paths.py` (`child_cwd` :104,
  `select_target` :186, `read_inside` :172–226), `broker/delegate_rules.py`
  (`REFUSED_FLAGS` :40, the sub tables :44–47, `_copy_name` :567, `_check_refused` :259),
  `broker/repocheck.py` (`DANGEROUS_KEY` :32, `resolve_member` :329–363, `owned` :366),
  `broker/gh.py` :61–64, `broker/services.py` (:106–110, :379).

## Files owned

- `broker/tests/test_a2x_hostile.py` — the suite.
- `broker/tests/util.py` — additive helpers only; no existing helper's behaviour changes.
- `broker/tests/fakes/{delegate,docker,git,gh}` — a new recorded mode of an existing fake
  only, where a case needs behaviour the four do not give (the state-file/`call_log`
  conventions stay). A *fifth* fake file is out of this step's declared scope: if a case
  truly needs one, report it as a deviation rather than adding it.
- `docs/specs/a2x-design.md` — a row's "expected" cell only, and only if the run proves a
  citation wrong; record it under DEVIATIONS.

No runtime file. A red line here is a2x-2's or a2x-3's finding, not this step's edit.

## Contract

One module, classes grouped by the table's families, each test named for its id
(`test_B03_line_over_max_line_refuses_too_large`). `broker/tests` conventions: the broker
listens on a socket in the test's temp root, `HOME`/`XDG_*` point there (design §3), the
sample projects are the fixture's `alpha`/`beta` — no site names or site paths anywhere.

**The shapes, cited once for the whole file.** A refusal is exactly one line
`{"ok": false, "error": <code>, "detail": DETAIL[code]}`, with `"arg"` only for a code that
rides its argument (truncated to `MAX_ARG` = 200, `protocol.py:434`) and `not_noreply`'s
`commits`/`count` extras — `protocol.answer_error` :422–437. Every test builds its expected
bytes by calling `protocol.answer_error(code, arg)` itself rather than re-typing the
sentence, so a DETAIL edit cannot pass silently and a refusal cannot drift. A code outside
DETAIL collapses to `failed` (:433), which is why asserting the *named* code is itself the
fence. A framing or grammar failure is `bad_request`; an unknown op is `unknown_op` **with
the op as `arg`** (`validate` :301) — different shapes, both pinned.

**Every refusal, in every case below, carries the three assertions design §3 demands**: the
exact bytes; no side effect (the fakes' `call_log` empty or exactly the allowed calls, no
spool left in the request directory, no marker file); and the audit line as §8 of the
contract describes it, with its `member` field present only when the answer is not in
`server.PRE_TARGET_CODES` (:610).

## Behaviour and edge cases

The module's cases, with the assertion each must carry (design §4's table is the case
list; this section says what "assert the exact shape" means per case, since that is where
the suites go wrong). Refusals from the *grammar* carry `arg`; the framing refusals do
not. `MAX_ARGV` is 64 (`protocol.py:23`), `MAX_STRING` 65536 (`:22`), `MAX_LINE` 262144
(`:21`), `MAX_REPO_NAME` 64 (`:33`), `MAX_ARG` 200 (`:24`).

**Framing (B3–B8).**
- B3: a request line of `MAX_LINE`+1 → `protocol.answer_error("too_large")` byte-exact,
  the connection then closed (`server.py:581–583`: the early refuse fires only once the
  line cannot become legal any more, and the test feeds exactly `MAX_LINE`+1 bytes plus a
  newline). The counter-case at `MAX_LINE`−1 well-formed JSON answers its own verdict,
  proving the reader is not off by one.
- B4: `argv` of 10 000 strings, and of 65 (over `MAX_ARGV`), and of 0 (under the 1) →
  `bad_request` byte-equal across all three (`protocol.py:330`), no further field read: a
  request that also breaks a *later* rule (`"op": "nope"`) answers `bad_request` for the
  shape first only when the shape rule is the earlier one — the order is framing → shape
  → op → keys → values (`validate` :291–303 reads top-down: `v`, then op-is-string, then
  op-in-OPS, then unknown-keys, then `_strings`, then the op's own field checks): the test
  constructs one request per pair of violations and pins which code wins, both directions.
- B5: `"argv": ["top", 42]`, `["top", ""]`, and a 100 KB string → `bad_request`
  (`_argv` :332 for the first two, `_strings` :397 for the third); the same 100 KB payload
  under a *key* → `bad_request` too (`_strings` checks keys as well, :400).
- B6: `op: "nope"`/`"delegate "`/`"Delegate"` → `unknown_op` **with** `"arg"` = the op
  (`protocol.py:301`), DETAIL's sentence unchanged; `op: 5`/`op: null` → `bad_request`
  (:294); `v: 1.0`, `v: true`, `v: "1"` → `bad_request` (:291, `type()` on purpose).
- B7: a line plus trailing bytes (`b"\n}"`) → `bad_request` (`_read_line` :587), closed;
  two requests on one connection → the second's bytes are never read: assert the answer to
  the first is `ok` and the connection dies silently afterwards (`_read_line` refuses
  anything after the newline before the loop ends, and the handler returns).
- B8: three deterministic halves of slow-loris: connect+close with no bytes (no answer,
  no traceback); half a line + close (`server.py:578–580`, "no answer"); one byte then
  idle to the 5.0 s deadline (`:60`, left at its default — the one timing test in the
  file, and it tests the deadline by *observing silence for it*, then a close) — and after
  each, a good request from a fresh `Peer` answers normally: the backlog of a hostile
  connection cannot starve the socket.

**Cross-project reach (B2, B9–B12).**
- B2: config written, project dir removed, request sent → `outside_project`
  (`server.py:399–405` for push/gh with a cwd; for delegate the same answer from
  `child_cwd`/`ProjectCtx` construction, `paths.py:104–122`); assert both ops and that the
  answer carries no path — the DETAIL sentence with no `arg` at all.
- B9: `cwd` `"sub"` (relative), `""`, `"//"`, `"/etc"`, `"/proc/self/cwd"`, and
  another project's real dir → the first two are `bad_request` (`_cwd` :358: a relative
  cwd is a shape error, the comment says the spec allows either answer and this is the one
  documented), the rest `outside_project`; `cwd` absent with one collab member → runs;
  absent with two members → `no_repo`, DETAIL cited, audit line names no member
  (`PRE_TARGET_CODES` :610).
- B10: the `repo` *request field*: `"a.b"`, `""`, `"-x"`, 65 chars, `".."` →
  `bad_request` (`_repo` :376, the daemon's `name_ok` imported not copied — the docstring's
  point is that the shape is refused before any lookup, so membership cannot be probed by
  shape); `"~"`, `"$HOME"`, `".hidden"`, `"web-app;rm"` → `bad_request` for the same rule;
  `"other"`, `"beta-member"`, `"api-svc"` (real member of the *other* fixture's project) →
  all three byte-**equal** `unknown_repo` (`resolve_member` collapses unknown/foreign/plain
  deliberately, `repocheck.py:329–363`); a read-only member → `not_a_target`; a
  plain-directory member → `unknown_repo`; `--repo` as an *argv flag* on any delegate verb
  → `refused_flag` with `arg="--repo"` (`REFUSED_FLAGS` :40, `_check_refused` :275).
- B11: two fixtures whose configs share one member directory on disk: project `alpha` asks
  `--repo` for a member `beta` also names → `unknown_repo` byte-equal to a truly-unknown
  name; and a config member whose name begins with `.` → the **config load** itself refuses
  (`config.py:316–323`, `_check_name`/`RESERVED_PROJECT_NAMES` :55) — this one belongs in
  the config test's style, not a socket request, and the socket half asserts that no
  request path can reach a dot-named member.
- B12: `top <id>` for the *other* fixture's real task id → `unknown_task` (`tasks.owned`
  false, `delegate_rules.py`); `run --name <slug>` claiming an id another project holds →
  `foreign_task` with the id as `arg` (`delegate_rules.py:628–647`); a `list` whose rows
  would span a shared repository → `shared_repo` (repocheck's view rule, contract §4.2);
  the three are different codes and the test pins which verb gives which — that mapping is
  the leak-surface, not the refusal.

**The rest of the grammar family (B23, B27, B29).**
- B23, the two faces of `--copy` × 51: as a `run` argv it dies in `_argv`, because the flags
  push the list past `MAX_ARGV` = 64 (`protocol.py:23`, `:330`) → `bad_request`, fake log
  empty; as a plan's `copy` list it **passes** (`_copy_ok`, `plans.py:195–202`: each name's
  shape, no count), so the test asserts what does happen — how many files reach the spool,
  that each is a plain file at 0600, and that a refused request leaves none (contract §11).
  The asymmetry (argv capped, list not) is the finding the row exists to record.
- B27, a `\u0000` inside a value three levels deep, and a line that is not valid UTF-8 at
  all: `bad_request` both ways (`_strings` :397–408; `parse_line`'s decode failure), with no
  `arg` and no echo — the assertion is that the request's literal bytes appear nowhere in the
  answer — and a fresh `Peer` afterwards answers normally.
- B29, the key shapes: a 200 KB key, an unknown key `argvv`, one line carrying `argv` twice,
  and an object where a string belongs. All `bad_request`: `_strings` recurses into keys
  (:400), `_keys_of` refuses the unknown (:310–326), `_no_dupes` refuses the duplicate
  (:374). The duplicate is the case worth its line — JSON's own last-wins would have let a
  request drop a flag it visibly sent, so the test pins the refusal, not a fallback.

**Grammar and op edges (B13–B15).**
- B13: the `service` op takes `name`/`kind`/`ttl` (`_keys_of` :315 → `SERVICE_KEYS`), not
  an argv: a hostile `name` (`"../../x"`, 200 chars, `""`) → `bad_request`
  (`_service` :199); `kind: "redis"` → `unknown_kind`; `ttl: "-1m"`, `"999h"`, `"30x"` →
  `bad_ttl` (:196); each with the fake-docker log **empty** — every one of these is
  answered before the spawn (contract §7).
- B14: `gh pr create …` with `github` absent from the config → `gh_refused` with
  `"arg": "<argv[0]> <argv[1]>"` (`gh.py:64`), fake-gh log empty; `gh` with an empty argv →
  `gh_refused` `arg = ""`… assert what the code gives (`gh.py:61` passes `argv[0] if argv
  else ""`, and `_argv` already refused the empty list with `bad_request` — pin the pair).
- B15: the `push` op `{"remote": "origin", "ref": "main", "force": true}` with `main` the
  default branch → `force_default` with `arg` naming the branch (`git_push.py:706/727`);
  the fake git's recorded argv contains the inspection reads and **no** `push` call;
  the noreply-hostile stack (a commit whose author is the reply address) → `not_noreply`
  with its `commits` list and `count` (`git_push.py:893/900` → `protocol.py:429–436`),
  compared as a parsed dict (the extras make byte-order comparison fragile and the
  contract specifies the *keys*, `:436`).

**Peer and audit (B1, and the audit half of every case above).**
- B1: `Fixture.peer(foreign_uid=<second uid>)` where the sandbox allows the peercred lie
  (util.py's own note) → the connection is closed with **no bytes at all** (the same
  answer `test_acceptance.py` pins; re-pinned here raw because the broker this slice faces
  has groups and service ops since) and `audit.log` gains a `peer_refused` line naming
  `peer=uid<N>` and nothing else (`server.py:149`, `audit.py:27` — the event is rate-gated
  at `PEER_AUDIT_GAP` 10 s, `server.py:33`: two refusals in the test window assert **one**
  line, which is the gate working).
- Audit discipline, asserted per refusal across the whole file: the line ends
  `ok=N code=<error>`, carries `project=<name>` and `op=<op>`, and the `member` field is
  present exactly when the answer is not in `PRE_TARGET_CODES` (`server.py:610–611`) —
  the tests that pin this on the happy path are `test_groups_hostile.py`'s; these are its
  mirror on the refused side, so a refusal that names a member it never settled fails.
- `arg` truncation (with B6): a 300-character unknown op answers `unknown_op` with
  `arg` of exactly `MAX_ARG`=200 characters (`protocol.py:434`) — the echo cannot carry a
  whole hostile payload, and the test measures the length rather than a prefix so a fix
  that truncates *early* is caught too.

## Acceptance criteria

- `python3 tools/run_tests.py broker.tests.test_a2x_hostile` exits 0 with every B1–B15 and
  B23/B27/B29 test present (`-v` counts it; the chain's fence is 18 `def test_B…` lines); the full gate green (`a2x-chain.json`'s verify, which
  greps `^ok broker.tests.test_a2x_hostile` out of the whole run).
- `git diff --name-only <base>` touches nothing outside Files owned (the chain's scope
  guard).
- The suite passes twice in a row from the same checkout (no leftover spool or audit
  state across runs) and with `TEST_TMPDIR` pointing outside `TMPDIR` (the runner sets it;
  `util.py`'s docstring says why).
- The report lists, per case, the assertion that would catch a regression, and any
  expectation this run had to correct against the code — those lines update the design's
  table and appear under DEVIATIONS.
## Out of scope

Filesystem/TOCTOU/copy/concurrency cases (B16–B31): step 2. The planner, the relay, the
live script, migration: steps 3–4. The daemon and A1's ledger. Any change to `broker/*.py`
runtime files — this step ships red lines to steps 2/3, not edits to the broker (the one
exception is `broker/tests/util.py`'s additive helpers, named in Files owned).

