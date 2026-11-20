# A2x design — slice 8 (A2 step 8): the hostile acceptance suite

Design for the last step of A2 (`docs/specs/a2-design.md` §11 step 8), as planned by ruling 26 at
the bottom of that file. This slice writes the acceptance tests that try to break the design on the
two layers the ruling names — the **in-process layer** (every hostile case a worker can run: real
component, real sockets, real parsing, fakes only at the external boundaries) goes into the gate,
and the **container layer** (probes only a live machine can answer) becomes the host-side script
`tools/a2-hostile-live.py`, whose unit tests run in the gate against fake executables but which is
run for real once, by the owner, at cutover. It adds no features. A hostile case that fails is
fixed in the component, not the test.

## 1. The list this slice is built to (binding, from the task and rulings 24–26)

Hostile cases, all required: **cross-project reach** (another project's broker socket, OpenCode on
4096, data dirs, worktrees, secrets); **egress proxy LAN side** (host Docker socket,
`/run/user/1000`, launcher/helper sockets); **GitHub token**; **`~/.ssh`**; broker
`--repo`/path tricks, `..`, absolute host paths, symlink and TOCTOU swap, hard link, FIFO/device;
NUL / newline / BiDi / 10000-char args; trailing newline past a `^…$` check; non-finite and huge
JSON numbers; oversized bodies and lines; a half-written request; 50 concurrent requests;
one-bad-among-good; git config attacks (`core.fsmonitor`, `core.hooksPath`, filter,
`diff.external`, `credential.helper` — none may run, marker absent); hub relay `/p/B/` with A's
credentials, `/p/%2e%2e/`, `/p/A%2fB/`, double-encoding, reserved names, mixed case, trailing dot
and slash, a WS upgrade to another project, `X-Forwarded-*` and `Host` claims; and hostile session
export JSON in migration (lands only in its own project's store or is refused).

Rules that shape every spec in the chain: tests set `HOME` and the XDG variables themselves and are
run under both an explicit mode set (umask `002`, XDG exported — the sandbox's shape) and a cleared
one (the host's shape), because a "world" group bit that is only an artifact of the host umask must
not read as a finding; free ports only; nothing ever touches the real home directory; no site value
(`hub/tests/test_anonymity.py` is the model); the suites use the shared fake-executable harness,
fakes stand for **boundaries** (docker, git remotes, gh, the delegate CLI, the egress proxy's
upstream) and never for the component under test — the broker is always the real `BrokerServer`,
the relay is always the real gate plus `Proxy`, migration is always the real functions fed with
fake docker executables.

## 2. Two layers, and where each case lives

| Layer | What it is | Where it runs |
| --- | --- | --- |
| in-process | real component + real unix socket / real `Proxy` / real planner, everything external faked | `tools/run_tests.py`, in the gate, every push |
| container | the same claims probed against the real engine as the container's own user | `tools/a2-hostile-live.py` on the host at cutover — never in the gate |

The in-process layer answers everything about *our code*. The container layer answers the questions
a mock structurally cannot: whether the **engine and kernel** enforce what we assume (uid 1324 cannot
open uid 1325's 0700 directory; a non-root container cannot mount; `--internal` really drops the
default route; the socket bind path really lives at `/run/{project}/broker.sock`). The chain is
ordered 1–4; steps 1–3 are the in-process layer split by component boundary (the broker side, the
hub relay, the planner/migration), step 4 is the live script plus its unit tests.

## 3. Coverage: every §10 threat row, its existing test, and what this slice adds

The rows are the §10 list of `docs/specs/a2-design.md` (the "Try to break the design" section the
rulings point at) and the threat table of `docs/specs/a2a-design.md` §11. Where a step-8 case adds
a *new* probe on top of an existing row, the case id (AX-…) is given and detailed in §5–§8.

Threat rows, named as in a2-design.md §10 ("prompt injection into a restricted session", "stolen
Google session → everyday hub", "a session reads another project's secrets", "broker bug (argv or
path injection)", "container escape (kernel)"), plus the extra probes the task's hostile list names;
rows marked *extra* come from that list, not the table.

| threat | existing test | what this slice adds |
| --- | --- | --- |
| prompt injection reaching the host (§10 row 1) | `hub/tests/test_gate_a2a.py` `test_row5_relay_to_project_denied_even_as_root`; `hub/tests/test_a2h_relay.py` X1–X25; `broker/tests/test_groups_hostile.py` | nothing new required at this row beyond re-proving the relay legs: **AX-R1..R12** drive the full socket pair (gate → `Proxy` → recorded upstream) rather than the gate alone |
| stolen session | `hub/tests/test_gate_a2a.py` (signing rows); `hub/tests/test_a2h_auth.py`; `hub/tests/test_a2h_routes.py` (project cookie rows) | **AX-R1, R9, R12**: a *valid* A session cannot reach B through the relay even when B exists, when B's socket is down, and when anonymous; the refusal is the gate's fixed 404 (`BODY_404 = {"error": "not found"}`, hub/gate.py:52) and never names B |
| other-project secrets via a compromised task | `broker/tests/test_groups_hostile.py` (B's socket → `not_member`, `SO_PEERCRED`, foreign-branch task ids); `hub/tests/test_a2h_routes.py` | **AX-X1..X6** (container layer): as uid 1324, open B's socket path, OpenCode's 4096 on B's IP, B's data dir and worktrees, B's `secrets/`, B's `.git`, and enumerate `/run/{project}` — all refused by mount/permission, and `/run/{project}` lists only A's socket |
| broker argv/path injection | `broker/tests/test_paths.py`, `test_repocheck.py`, `test_groups.py`, `test_server.py` | **AX-B1..B12** (framing and validation depth), **AX-F1..F10** (`--repo`/path tricks incl. TOCTOU swap, hard link, FIFO, device), **AX-G1..G6** (git config attacks with a marker file), **AX-C1..C3** (one-bad-among-good, trailing newline past `^…$`, 10000-char args) |
| container escape (explicitly out of A2's scope) | — | the container layer re-proves the *cheap* escapes are shut: mount denied (**AX-X7**), `capsh --print` shows no caps (**AX-X8**) — a finding here is escalation to the owner, not a fix in this slice, per a2-design.md §9 |
| egress proxy LAN side (host Docker socket, `/run/user/1000`, launcher/helper sockets) | `hub/tests/test_a2h_accept.py` (X16: proxy dials 172.16.0.0/12 and is refused) | **AX-E1..E5** (container layer): through `http://$EGRESS:8888` fetch `http://127.0.0.1:2375`, `http://[::1]:2375`, `http://localhost:2375`, a `GET /v1.45/containers/json` style path, and the host gateway's launcher port — every one refused (4xx from the proxy, or ECONNREFUSED), nothing dialed |
| GitHub token and `~/.ssh` unreachable from a container | launcher/host tests assert placement modes on the host | **AX-S1..S3** (container layer): stat `{home}/.ssh` and `/run/secrets/github-token`-shaped paths (EACCES or absent for other projects), and prove `~/.claude`, `~/.config/gh`, `~/.local/state/opencode` are container-local by writing a sentinel to `~/.x` inside, re-execing, and checking the sentinel is on the container bind, not on the host's real path |
| admin plane (all a2a §11 rows) | see §3b — one row each | relay-leg versions of the hub-scope rows only; the launcher rows stay in their suite (§3b says which file, per row) |

### 3b. a2a-design.md §11, row by row

The a2a hostile suites (`hub/tests/test_gate_a2a.py`, `launcher/tests/test_a2a_hostile.py`) are the
a2a chain's deliverables on this same base; a citation here that the file is not yet on the branch
means "owned by the a2a step named", never "missing". **None of this slice's verify commands greps
for those modules** — the table is coverage bookkeeping, not a dependency. "A2x adds" is `none`
wherever the row's enforcement lives outside this slice's four components (gate/proxy relay, broker,
oc, live probes); duplicating launcher/Claude-profile cases in the acceptance suite would add gate
minutes, not claims.

| a2a §11 threat row | covering test | A2x adds |
| --- | --- | --- |
| Stolen Google session opens/extends a project admin session | `launcher/tests/test_a2a_hostile.py` (D7/D8/D9 rows) | none (launcher plane) |
| Container plants code the host admin session runs (hooks, MCP, plugins, git programs, fake helper) | `launcher/tests/test_a2a_hostile.py`; the git-program half is *our* half: **AX-G1..G6** | G-rows re-prove the `.git/config` surface from the broker side, including the accepted residual (filter/diff driver added mid-session): the broker's `HARD` flags make the residual empty **for broker calls** — asserted |
| Hijacked project admin acts outside its project (prompt injection row) | `launcher/tests/test_a2a_hostile.py`; container side: launcher unit env tests | **AX-X2..X4, AX-E1..E5** — the container's own reach map, measured not assumed |
| Hijacked project admin acts on another project | `launcher/tests/test_a2a_hostile.py`; `broker/tests/test_groups_hostile.py` | **AX-C6** reach-map sweep; **AX-X1** (only A's socket is even visible) |
| Container plants a compose-project label | `launcher/tests/test_a2a_hostile.py` | none — a container here has no Docker access; **AX-E1/E2** re-prove the socket is undialable, which is the premise |
| Container log output attacks agent/terminal (escapes, floods) | `launcher/tests/test_a2a_hostile.py` (cleaning rules) | **AX-B7** is the same poison refused at the broker's *input* door — the protocol now rejects directional/ESC chars instead of cleaning them |
| Container writes the admin folder / generated profiles | `launcher/tests/test_a2a_hostile.py` (700-dir rows) | none (never mounted here — **AX-X4** shows absence directly) |
| Session leaves files in admin folder / rewrites profiles | `launcher/tests/test_a2a_hostile.py` (rebuild rows) | none (launcher plane) |
| Compose file deploys a host takeover | `launcher/tests/test_a2a_hostile.py` (validator rows) | none — but **AX-X7/AX-X8** check the engine premises (no caps, no mount) that make the validator's job survivable |
| Allow-listed external network reaches other services | accepted (owner 2026-11-18) | none — recorded as accepted; the OpenCode/egress networks themselves are **never** on an allow-list here (`create_argv` pin, AX-P6) |
| container_name takeover/impersonation | `launcher/tests/test_a2a_hostile.py` (label rows) | none (compose plane); `{project}-oc-` prefix refusal for *this* plane is the planner's own name (`CONTAINER_PREFIX`, pin AX-P6) |
| Admin reads/changes another project's secrets | `launcher/tests/test_a2a_hostile.py` (deny-by-name rows) | the container-side twin: **AX-P2** (no member holds the data root), **AX-X4** |
| OpenCode container reads the secrets | `launcher/tests/test_a2a_hostile.py` doctor rows; `oc/tests/test_projects.py` | **AX-P3** (symlinked secret source), **AX-S3** (sentinel proves HOME-local), **AX-S1** (token never in an outbound request) |
| Compose action races another | `launcher/tests/test_a2a_hostile.py` (lock rows) | none (compose plane) |
| Config text injected into briefing/permission rule (newline, backtick, bidi names) | `launcher/tests/test_a2a_hostile.py` (`unsafe_member` rows) | the broker-side twin at the input door: **AX-B5/B7**, **AX-P1** (names carrying the same poisons never reach a path/unit), and the raw-path rows **AX-R2/R3** for the URL carrier |
| Prompt injection via member `CLAUDE.md`/`AGENTS.md` | accepted (row says so); `launcher/tests/` | none |
| Owner's user-level Claude settings widen the profile | `launcher/tests/test_doctor.py` warnings | none (not mounted here; **AX-X3** stats it as absent-or-local) |
| Crafted project/member name reaches a path, unit, tmux target | `launcher/tests/test_a2a_hostile.py`; `broker/tests/test_groups_hostile.py` | **AX-F1/F2** (broker door), **AX-P1** (planner door), **AX-M5/M7** (migration door) — every entry point gets the sweep |
| Forged request picks read-only/foreign member | `broker/tests/test_groups_hostile.py`, `test_groups.py` | none new beyond **AX-F7/F9** (claims never open anything; foreign task ids across logs/kill/cleanup) |
| Ended session's terminal stays reachable | `hub/tests/test_a2h_shell.py`, `launcher/tests/test_ptybridge.py` | none — relay-leg re-proof is X12's sibling already in **AX-R8**'s harness |
| One project's admin request acts on another project's unit | `launcher/tests/test_a2a_hostile.py` (every pair driven) | none (launcher plane) |
| Work view credits wrong project | `launcher/tests/test_audit.py` string-rule rows | none (audit plane; our audit lines carry only codes — asserted in AX-C6) |

## 4. The shared harness: fake executables (`broker/tests/fakebin.py`)

The task requires fake *executables* for docker, git remotes and gh that record their argv — the
largest class of hostile claims is "the component ran exactly this command and nothing else".
`broker/tests/util.py` already does this per-module with an sh-script farm (delegate, docker, gh,
git; each appends one JSON line to `$FAKE_BIN_LOG`); step 1 generalizes that pattern into
`broker/tests/fakebin.py`, importable by the `broker`, `oc`, `hub` and `tools` suites:

* `FakeBin(dir, name, *actions)` — writes an executable that appends
  `{"argv": [...], "cwd": ..., "env": {...selected}}` to `<dir>/binlog`, then acts out the actions:
  `exit N`, `stdout TEXT`, `sleep S`, `mk PATH` (the fake touches a file — proof of what *it* can
  reach), `tee PATH`;
* the log is the assertion source: "no hidden pipeline", "exactly one subprocess", "the token never
  appeared in any argv" are each one read away;
* a **forwarding** git fake (`forward=True`) execs the real `/usr/bin/git` after recording, so
  push-check cases run against a *real* bare remote (real `receive.denyCurrentBranch`, real
  pre-receive hook) — the remote is never a mock. Where forwarding would let an attack *execute*
  (the fsmonitor/hooks cases) the fake does not forward: recording and refusing is the point.

No fake stands in for the component under test: the broker is always the real `BrokerServer` over a
real unix socket, the relay is always the real `decide()` + `Proxy`, migration always runs its real
functions against fakebin docker. This mirrors the sh-farm rules at broker/tests/util.py:95-121.

## 5. Broker-side hostile cases (step a2x-1, in-process)

Every refusal asserts the documented wire shape `{"ok": false, "error": CODE, "detail": …}` with
`detail` from `protocol.DETAIL` (the fixed table `docs/specs/a2-2a-broker-core.md` names), and side
effects asserted absent; the client-side shape is exit **125** for a broker refusal and **69**
(`EX_UNAVAILABLE`) for no broker / a cut / garbage (`broker/client.py:45-46`).

**Framing and validation (AX-B1..B15)** — written to the raw socket; one client-level case re-sends
the same shapes through `client.main` and asserts the exit codes:

| id | sent | expected |
| --- | --- | --- |
| AX-B1 | `not json\n`, bare `[`, `{}`, `1`, `"x"`, empty line | one `bad_request` line then close (`server.py` `_Conn.serve`, json branch) |
| AX-B2 | `v` of 2, `"1"`, `1.0`, `true`, missing | `bad_request` — `type(…) is not int` (protocol.py:292) |
| AX-B3 | `op` `exec`, `shell`, `"status extra"`, 10 KB name | `unknown_op` with the `arg` echo — answered, never guessed (protocol.py:297) |
| AX-B4 | `push` minus `ref`; any extra key; `argv: []`, not a list, 65 entries, non-string entry | `bad_request` (`_argv`, `_push`, protocol.py:318-363) |
| AX-B5 | NUL in any string at any depth — dict **keys** included | `bad_request` (`_strings` recurses keys, protocol.py:400-411) |
| AX-B6 | newline/tab inside run `argv`/`task` | **accepted, inert**: byte-exact at the fake, exactly one response line — JSON escaping makes `\n` unable to forge a frame, and a task text is legitimately multiline (DECISION, §11) |
| AX-B7 | U+202E, U+2066, U+200F, ESC (U+001B) in any string | `bad_request` — **fails against today's `_strings`**, which checks only NUL/length/surrogates; step 1 fixes the component (the a2-2a spec already promised control/BiDi refusal): refuse category Cc except `\t\n\r` and the directional Cf set {U+200E, U+200F, U+202A–U+202E, U+2066–U+2069} |
| AX-B8 | 10000-char argv entry to `delegate`/`gh` | `bad_request` — `MAX_ARG_LEN = 1024` (delegate_rules.py:25); to `run`: accepted under `MAX_STRING` and byte-exact at the fake; 65537 chars → `bad_request` for every op (`_strings`) |
| AX-B9 | `cwd` relative, `cwd` a number | `bad_request` (`_cwd`: a relative cwd is a shape error, protocol.py:368-376) |
| AX-B10 | `v`: NaN, Infinity, -1e999, 10\*\*400; a number where a string belongs | `bad_request` every way (floats fail the `type is int` check; 10\*\*400 the `!= 1`); never a hang, never a closed silence (client: 69 on close, tested once) |
| AX-B11 | a 4 MB line; an exactly-`MAX_LINE` valid line | `too_large` + close — the server reads at most `readline(MAX_LINE + 2)` (protocol.MAX_LINE = 262144, protocol.py:24); the exactly-capped line answered normally (boundary inclusive) |
| AX-B12 | `}` + trailing newline + junk; two requests glued `}{`; a pipelined second request on one connection | glued is **one** `bad_request` (one line = one request); after one answer the server closes, so the pipelined remainder gets nothing and the client maps the cut to 69 — never two answers to one socket |
| AX-B13 | `{"v":1,"op":"st` then silence | refused at `request_deadline` and closed (server's deadline knob — pass 0.2 s); the handler thread is gone after (`_Conn` is one thread per connection, server.py:76-81); a later good request still answers |
| AX-B14 | **50 concurrent connections** against `MAX_CONNECTIONS = 8` (server.py:39, `admit()` at server.py:103-108) | every connection served or closed-without-a-line by the cap; no crash; once slots free, retried connections all get correct one-line answers; liveness proven by a final good `status` |
| AX-B15 | half-close from the client side: fake broker that accepts and never answers | client exits 69 with its read deadline (client.py's timeout path), never hangs past it |

**`--repo` / path tricks and the view (AX-F1..F10)** — real repocheck/view code over
`Fixture`-style member farms (cites `docs/specs/a2-groups-contract.md` §4.1 and the a2-4b view
contract):

| id | attack | expected |
| --- | --- | --- |
| AX-F1 | `repo` = `..`, `.`, `../..`, `web/../secrets`, empty, `.web`, `web.` | `bad_request` before any lookup — the shape rule is the daemon's `name_ok` imported, not copied (protocol.py `_repo`, protocol.py:390-401: "one member name, never a path"); refusal shape identical whether or not a member bears the name (no membership oracle) |
| AX-F2 | `repo` = `web/inside`, `/web`, `~/web`, `web%2finside` | `bad_request` — no `/` survives `name_ok`; the percent form fails the same shape test, byte-for-byte |
| AX-F3 | member registered with a **symlinked** worktree path out of the project root | the resolved real path fails containment → `unknown_repo` (a real-path answer at registration, never a leak of the target — DETAIL sentence has no `/`) |
| AX-F4 | **TOCTOU swap**: member dir swapped for a symlink-to-outside between the containment check and the read | `paths.read_inside` resolves once and compares by `SameFileError` on the re-open (paths.py:120-162); the swap between *directory resolve and file open* and between *file open and fd re-resolve* both refused → None; plus a view-level case that swaps between `view()` and spawn and asserts the refusal code, never an open |
| AX-F5 | member is a **hard link** farm: `.git/HEAD` hardlinked from another project's file | containment judges the resolved *path*, and a hard link resolves inside its own tree — the case asserts the second project's *content* is only visible if its path is under this root (it is not → refusal), and the marker file the other tree owns is never opened |
| AX-F6 | member path is a **FIFO** or **/dev/null** (planted directly in the project config) | `NotAGitRepo` from `rev-parse` (repocheck.py:153-155) → `unknown_repo`; nothing blocks: the first subprocess is git with a 10 s timeout, and the fake's recorded argv proves it |
| AX-F7 | `cwd` claim = another project's worktree, `/`, a foreign member dir | membership decides, the claim never opens anything: `no_repo` / `not_member` per §4.1's three answers (a request's cwd is an assertion, protocol.py docstring; audit line says only the codes) |
| AX-F8 | branch values `--upload-pack=evil`, `+refs/heads/x`, `origin/x`, `HEAD~99999`, `<stdin>`, a 1 MB name | never reaches a subprocess position that could act: refs are checked with `rev-parse --symbolic-full-name` before anything rides (repocheck.py:187); push refuses a forced ref before the remote (`force_default`, a2-3a checks); oversized → `bad_request` by `_strings` |
| AX-F9 | B's live task id claimed to A: `status`/`logs`/`kill`/`cleanup` | not found — the lookup is scoped to the claiming project's state dir first (groups contract §6; `test_groups_hostile.py` covers `status`, this suite extends it to **logs/kill/cleanup against B's live task**, asserting the fake delegate recorded no signal and B's run dir unchanged) |
| AX-F10 | `service` name `../../etc/passwd`, `web;rm -rf /`, `web --volume=/`, uppercase of an existing name | shape refusal before any docker call (a2-4e §5's name/label regexes) → `bad_request`; the fake docker records **zero** invocations |

**Git config attacks (AX-G1..G6)** — an attacker-collaborated repository the owner registered;
after every case the marker file the planted config would touch **must not exist** (cites
`repocheck.DANGEROUS_KEY`, broker/repocheck.py:32-36, and its `HARD` flags `-c
core.hooksPath=/dev/null -c core.fsmonitor=false`, repocheck.py:36):

| id | planted in `.git/config` (and `config.worktree` for the worktree scope) | expected |
| --- | --- | --- |
| AX-G1 | `core.fsmonitor = <marker-writer>` | `inspect` answers `unsafe_config` (repocheck.py:73 matches the key whatever the value); marker absent; fake git records no invocation beyond the config reads |
| AX-G2 | `core.hooksPath` → a dir whose `pre-commit` writes the marker | `unsafe_config`; and even when the key is *absent*, every inspect-side call carries `HARD` so a `pre-commit` never runs — the recording-forwarding git fake shows both the flags and the marker absent |
| AX-G3 | `filter.l.smudge`/`filter.l.clean` = marker-writer, plus a `.gitattributes` routing `*` through it | `unsafe_config` (`filter\..+` matches); `git show HEAD:file` spawns no filter anyway (no checkout) — the forwarding fake records exactly that argv |
| AX-G4 | `diff.mark.command` / `diff.external` = marker-writer | `unsafe_config` (`diff\..*` family, repocheck.py:34); marker absent |
| AX-G5 | `credential.helper = !/bin/sh -c 'touch <marker>'` + `remote.origin.url = ext::sh -c 'touch <marker>'` | the helper key alone → `unsafe_config` (include/credential rules); `ext::` never matches a `url_patterns` `fullmatch` → `not_github` (git_push.py:309-316, "the url itself is never named"), so the push never runs a transport; push env carries the blanked `GIT_ASKPASS=`/`GCM_PROVIDER=` (a2-3a spec) — shown on the recording fake; marker absent |
| AX-G6 | the same five keys with *benign* values (`core.fsmonitor=false` as a repo key, `core.hooksPath=.git/hooks`) | refuse anyway — the table matches the key, not the value (repocheck.py:33's `\A…` fullmatch); this case pins that rule so no later "smart" relaxation can slip in |

**One-bad-among-good, `^…$` pasted, and batch size (AX-C1..C4)**: a member farm of eight good
repos and one poisoned (AX-G1's config) → `status`/`view` answer per member with that member's code,
healthy members unaffected, the poisoned member's git never run (fake log); every anchored check in
the broker gets a trailing-newline payload (`noreply@x.github.com\n` as an author, a targets JSON
with trailing `\n`, `\r`-terminated ref) — each answers with its documented refusal or inert-
equivalence, never a pass (the noreply check is `fullmatch`, git_push.py:395-396, which `\n` cannot
slip the way a `$` match would — this case *pins* that it stays `fullmatch`); a `status` reply
whose payload would exceed `MAX_LINE` when serialized (a member list of 64 × fat paths) → the
answer is capped or refused per §"the answer never frames-fragments" (a2-2a wire contract: one
line ≤ MAX_LINE) — assert the server never writes a fragment; 10000-char args run the whole matrix
× {run, delegate, gh, push, service} in one sweep, survivors exactly as AX-B8 names.

**Audit failure stays a refusal (AX-C5)**: a state dir whose audit file is a directory → the answer
is the catch-all's `failed` line (`_run_safely`, server.py:355-373 — traceback to the broker log,
never to the wire), the connection is not left half-written, and the next request on a fresh
connection still works.

**Cross-project in the same suite (AX-C6)**: `test_groups_hostile.py` proved the *request* layer
(B's request seen by A's server is `not_member`). What this slice adds is the *reach map as a
table*: one broker, one member farm spanning two projects' paths, and a swept assertion that for
every path-shaped input (cwd claim, repo claim, task id) the answer is one of the three documented
codes and the fake's binlog contains **no git or docker invocation referencing the other project's
path** — the path itself never echoes back (`DETAIL` sentences carry no `/`, protocol.py:100-124).
The 0600-socket / uid-1325 separation behind that table is a container-layer claim: **AX-X1** in the
live script.

## 6. Hub relay hostile cases (step a2x-2, in-process)

Harness: the real gate (`gate.decide` chain) + the real `Proxy` against a fake container upstream
that records every dialed request (`hub/tests/test_a2h_relay.py`'s pattern — reused, not re-faked).
The fixed bodies: `BODY_400 {"error": "bad request"}`, `BODY_401 {"error": "unauthorized"}`,
`BODY_403 {"error": "forbidden"}`, `BODY_404 {"error": "not found"}` (hub/gate.py:49-53); a routed
project failure answers from `proxy.body_project_offline(project)` (proxy.py:170-171). Every case
asserts the fake upstream recorded **zero** dialed bytes unless the row says it should be dialed.

| id | request | expected (documented shape) |
| --- | --- | --- |
| AX-R1 | `GET /p/B/api/session` carrying A's project session cookie | fixed `BODY_404` — a project session never names the other project and nothing before routing can conjure one; the audit line's host slot is `p/B` (proxy.py:261-266) but the *session value* never appears anywhere |
| AX-R2 | `/p/%2e%2e/api/x`, `/p/%2E%2E/`, `/p/..%2fB/api` | `%2e` anywhere → `BODY_400` at the request-line step (gate.py:291, §10.3); `..%2f` survives hygiene but the P1 matcher compares **raw bytes** (routes.py `_project_api`, 198-205) → `BODY_404`; never a dial |
| AX-R3 | `/p/A%2fB/api/x` | `BODY_404` — the matcher byte-compares, so the encoded slash is just an unknown name (routes.py:198-205); unlike the host segment's `%2f` 400 rule (gate.py:294), which the sweep includes to pin the two rules stay where they are |
| AX-R4 | double encoding: `/p/%252e%252e/api`, `/p/%252f/api` | hygiene passes (no `%2e` token), raw match fails → `BODY_404`; one decode still wouldn't route (no re-decode anywhere — the raw-is-truth rule, a2h-design §4.1) |
| AX-R5 | every reserved name: `/p/p/api`, `/p/api/api`, `/p/auth/api`, `/p/settings/api`, … with a valid admin session | `BODY_404` identical to a nonexistent project — indistinguishable; the reserved list is `broker/config.py:55` (`RESERVED_PROJECT_NAMES`) mirrored in the hub's project set construction; a project that *wants* to be named `p` cannot be created (AX-P1) |
| AX-R6 | mixed case `/p/ALPHA/api/x`, `/p/alpha/API/x`; trailing dot `/p/A./api/x`, `/p/A../api/x` | `BODY_404` all — byte-for-byte comparison, no `lower()`, and the dot forms are not dot *segments* (they pass gate.py:300's `.`/`..`-exactly test) yet fail the byte match; the *host* segment has its own lowering rule the sweep pins (gate.py:290) |
| AX-R7 | trailing forms: `/p/A/api/` (routes), `/p/A/API/`, `/p/A/apix`, `/p/A` alone | the first is ordinary relay traffic; the rest fall to `BODY_404` exactly as the matcher's docstring enumerates (routes.py:200-204) |
| AX-R8 | WS upgrade `GET /p/A/api/pty/<id>/connect` with A's valid project session and correct `Origin` | dialed exactly once to **A's** upstream with the PTY upgrade headers (the existing X12 case; this slice re-runs it end-to-end through `Proxy` and asserts the password rides A's upstream object only — proxy.py:373-376 "one project's password can never ride another project's url") |
| AX-R9 | the same upgrade aimed at `/p/B/…` with A's cookie | `BODY_404`, never upgraded; then `/p/B/…` with the admin session while B's upstream socket is **down** → routed (admin may cross, ruling: the admin relay exists) and answered `body_project_offline("B")` with 502 — the two refusals must not be confusable |
| AX-R10 | `X-Forwarded-Prefix: /p/B`, `X-Forwarded-Host: B`, `Forwarded: _=`, `X-Forwarded-Proto: http` on a legit A call | the relayed request carries the gate's own computed prefix only — the fake upstream shows the client's claims absent or overridden (X5/X23 pattern); the browser's returned paths still say `/p/A/` |
| AX-R11 | cross-site `Origin` on `POST /p/A/api/session` | `BODY_403` at the origin step, before routing (X9's rule, gate.py `_step_origin`); `Origin: null` included |
| AX-R12 | anonymous `/p/A/api/session`; project session aimed at the **home** origin's path (`/session` bare) | `BODY_401` for the anonymous relay (X8); a project session presented on the home origin is not an identity there — the home answers as anonymous (verifier scope, a2h-3 contract); no cross-bleed either direction |
| AX-R13 | one `GET /p/A/api/session` carrying **20 cookies** (A's valid one among junk) and a `Cookie` header of 32 KB | the gate's framing rules answer their fixed bodies (gate.py §4.2: one digit-only `Content-Length`, no obs-fold — the worker cites the step the sweep hits, `BODY_400`/`BODY_401`); one-bad-among-good must still authenticate A when within every size rule |

## 7. Planner and migration hostile cases (step a2x-3, in-process)

The planner's hostile surface is the **project record**: everything a registry entry can claim
becomes argv, so the sweep feeds records, not sockets (cites `docs/specs/a2h-design.md` §5 and
`oc/projects.py`'s module docstring: "the mounts are `broker.mounts.mounts` and nothing else").
Migration's surface is the **export document**: `docker exec … {project}-broker export` output is
attacker-writable the moment a container is compromised, so every parse rule is a hostile input
(cites `oc/migrate.py`'s `REASONS` tuple, migrate.py:51-53 — every refusal names one, no free text
beside it).

| id | input | expected (documented shape) |
| --- | --- | --- |
| AX-P1 | project name `..`, `.ssh`, `a/b`, absolute path, 64 chars, `A` (uppercase), name with trailing dot | refused at load: `daemon.config._name_ok` **and** `NAME_RE` both stand, imported not copied (projects.py:858-862, projects.py:48); a `PlanError`/registry error naming the key, never echoing the value's tail (`_brief`, projects.py:167) |
| AX-P2 | member path `..`, `/`, the data root itself (`<data>/{project}` — every project's passwords live there), a member inside another project's layout, a sibling-prefix trick (`/srv/proj-a` vs `/srv/proj-ab`) | `_check_mount_value` refuses paths that "hold" protected roots (projects.py:183), `_check_not_trusted` refuses member mounts over another project's data (projects.py:188-196); the prefix case must **pass** planning (two real projects may sit so) yet still get disjoint mounts — asserted on the final `create_argv` |
| AX-P3 | `extra_mount` whose source is a symlink to `/`, to `/etc/shadow`, to another project's `secrets/`; one with `ro=False` aimed at the broker sock dir | `binds()` resolves before deciding (same resolve-first rule as `paths.py`); the broker-dir bind is mounted `read_only=True` no matter what the record claims (projects.py:235), and a secret-file mount must be a plain absolute file (projects.py:241) → `PlanError("secret-file", …)` |
| AX-P4 | 17th through 20th project (subnet reuse) + two projects whose slugs collide mod 16 | planner's documented rule, not a bug: each project still gets **its own named `--internal` network** (`network_argv`, projects.py:~370) — isolation is by network identity; the sweep asserts no two projects share an upstream object, and `create_argv` never carries another project's socket path or password file |
| AX-P5 | record with a worktree path that is a FIFO / a symlink whose target vanishes between resolve and plan | `PlanError` at bind validation (the resolve-first failure is a planning refusal, not a docker-time surprise); zero docker invocations recorded |
| AX-P6 | env sweep: `create_argv` for a fully-populated hostile record, scanned token by token | no argv entry contains `~/.ssh`, `/run/user`, the host docker socket, another project's name, or the GitHub token path; `--cap-drop ALL`, `--security-opt no-new-privileges`, `--read-only` (where the design says so), `-p 127.0.0.1:…:4096` loopback-published, `--user` the project's uid — the pin list the spec enumerates from the current `_create_body` |
| AX-M1 | export doc: valid JSON list, a bare string, `null`, a number; `{"id": …}` missing `messages`; `messages` a dict | every malformed doc answers the documented reason for the session (`export_failed` when the *fake docker* exits nonzero — that is what the fake plays; parse-level junk inside an otherwise-valid export answers `verify_failed`/`import_failed` per migrate.py's flow — worker cites the exact branch) and **no directory outside the project's own store is created** |
| AX-M2 | `id` = `../../evil`, `a/b`, empty, 300 chars, NUL, newline, `..`; id colliding with an existing session's | id sanitized before it names a file — either refused (a `REASONS` value) or hashed to a safe name; the case asserts the store dir contains only the project's sessions afterwards, and a collision is a **new** copy, never an overwrite (migrate.py's assign rule, cited by the worker at write time) |
| AX-M3 | hostile session **titles** (`\x00`, `\n`, U+202E, 1 MB), message content with control chars | carried verbatim into the store (it is data, not a command) or refused for size by the documented cap (`too_large`) — the invariant both outcomes share: the broker/view never sees it unquoted, and the store file parses back byte-exact |
| AX-M4 | doc claiming 10,001 sessions; one whose messages array is 50 MB | `too_large` / capped per migrate's documented size rule (migrate.py:51 — `REASONS` includes it, so a refusal shape exists); memory bounded (the fake streams the doc with a slow writer); project store still consistent |
| AX-M5 | the `--project` flag itself hostile: `..`, `$(reboot)`, a name not in the registry, two `--project` flags | refused before any docker exec runs: `no_project` reason / usage exit 2 (migrate.py's `Usage`, migrate.py:56-58 — flag errors are the usage line, exit 2, never a partial run); fake docker records **zero** argv lines |
| AX-M6 | one-bad-among-good: 10 exports, #7 hostile (AX-M2 id, #9 huge) | the other nine carry, #7/#9 get their reasons, the run's summary line lists both, exit code per migrate's documented partial-failure rule; the bad session leaves no partial directory (atomic-per-session write — worker cites where migrate guarantees it) |
| AX-M7 | `_assign_project` fed `..` / `/` / empty / 64-char / mixed-case names | the documented rule: names that cannot own a directory get `no_project`/unassigned (migrate.py:51 REASONS) — never a `..` path join, asserted by scanning every recorded docker exec argv for `..` and `{home}/` shapes |

Every AX-M case runs against the **fake docker executable** on `PATH` (fakebin) that replays
`{project}-broker export` output from a fixture the test supplies — the real `migrate` code under its
real argv, boundary faked only at `docker`.

## 8. The live container layer: `tools/a2-hostile-live.py` (step a2x-4)

A host-side stdlib script, run by the owner at cutover, never in the gate (no Docker here, and the
gate must stay runnable on any machine). Shape:

* `usage: a2-hostile-live.py --project A --other B [--dry-run] [--json]` — refuses (exit 2) unless
  **both** names are in the launcher registry read read-only from
  `~/.local/state/{project}-launcher/projects.json` (the registry path `launcher/oc.py` defines);
  no container-name guessing, no `--force`;
* every probe runs as `docker exec --user <container's own user> <container> …` against A's real
  container; the script itself only reads, connects, and attempts requests **from inside**;
* prints one `PASS <id>` / `FAIL <id> <one-line expected-vs-actual>` per probe and exits non-zero on
  any FAIL; `--dry-run` prints the whole probe plan as JSON and exits 0 without touching docker;
* **never changes state**: the rule is exact — allowed are `stat`/`ls`/`cat` of files, read-only
  connects (unix, tcp, the proxy), and requests that must be refused; forbidden are writes anywhere
  except `/tmp` inside the container (a marker file there, deleted by the same probe that made it),
  `docker create/start/stop/restart/rm/exec-as-other-user`, signal, network admin, and anything to
  the host filesystem outside the container. A probe that needs a side effect to prove it (the
  sentinel test AX-S3) is written as create-in-container-/tmp plus re-exec and is skipped, not
  forced, if even that would persist — the skip prints `SKIP <id> <why>` and counts as neither pass
  nor fail (the owner decides);
* unit tests in the gate (`tools/tests/test_a2_hostile_live.py`, new suite dir — `tools` is already
  in `run_tests.py`'s SUITES) put a **fake `docker` executable** on `PATH` (fakebin reused) that
  replays canned probe outputs, and cover: all-pass → exit 0 with every `PASS` line; one fail
  replayed → exit 1 with exactly that `FAIL`; docker missing → a documented "cannot run" error, not
  a traceback; `--dry-run` output shape; registry-guard refusal before any docker call (the fake
  records zero argv); and the never-change-state rule asserted **structurally**: every argv the
  script ever execs is scanned for the forbidden verbs (`rm`, `stop`, `write`, `>`, `tee`), a
  violation being itself a unit-test failure.

Probe list (each: what it runs inside, expected, why a mock could not say it):

| id | probe | expected |
| --- | --- | --- |
| AX-X1 | `ls -l /run/{project}`; attempt `python3 -c 'import socket;s=socket.socket(socket.AF_UNIX);s.connect("/run/{project}/broker.sock")'` **and** B's known socket path if bind-visible | `/run/{project}` lists only A's `broker.sock`; connecting A's own socket as the container user works (it is the contract), and B's path is unreachable because it was never mounted — a bind-mounting failure shows as FAIL here, which is exactly what the layer is for |
| AX-X2 | `curl -sf http://<B's ip>:4096/` and `python3` connect to B's ip:4096, B's ip derived from the registry + `/28` layout the planner documents (not guessed) | connection refused / no route — `--internal` boundaries are engine-enforced |
| AX-X3 | `stat {home}/.ssh`; `id -u` is 1324-1340 shape; `stat ~/.claude`, `~/.config/gh` | `.ssh` absent or EACCES; the HOME paths are the container bind's, proven by AX-S3's sentinel |
| AX-X4 | enumerate the data dir: `ls <data>/{project}` visible inside | only A's own subtree is mounted in; other projects' directories physically absent from the bind |
| AX-X5 | `git -C <member worktree> config --get-all core.fsmonitor` and friendlier reads while a host-side marker check confirms nothing ran | values are the owner's own config; the engine's `safe.directory` story (`repocheck` runs as the same uid) holds; no marker touched |
| AX-E1..E5 | `http://127.0.0.1:2375/`, `http://[::1]:2375/`, `http://localhost:2375/`, `http://<gateway-ip>/run/user/1000/{project}-launcher/launcher.sock` (path-shaped URL), and `http://<gateway-ip>:<launcher-port>/status` — with `--helper-sock PATH` allowed to add the a2a helper's socket as E4b (never guessed from anything else); all **through the egress proxy** (`http_proxy=$EGRESS:8888` honored by the probe tooling) | every one refused by the proxy's LAN-side rule (403 class) or ECONNREFUSED; the proxy's own log line (read over `docker logs --tail`, a read) shows the deny; no response body is ever proxied |
| AX-S1 | attempt `GET http://<any allowlisted host>/x` with `Authorization: bearer` injected via the allowlist-only env the proxy already holds | the token stays inside the proxy container: the probe's outbound request must not carry it — the fake upstream (delegate's egress test page or an httpbin on the allowlist) would show it; at cutover the owner may substitute their own echo endpoint with `--echo-url` |
| AX-S3 | write sentinel to `~/.x-probe-$$` inside, `cat` it back, `stat` the host's real `~/.x-probe-$$` from the host side **read-only**, delete the container file | the sentinel exists only inside the bind — `~/.claude` etc. are container-local |
| AX-X7 | `mount -t tmpfs none /tmp` and `unshare -U true` | `mount`: permission denied (non-root, cap-drop ALL); `unshare`: either denied or an isolated namespace with no new powers — both outcomes documented, the probe fails only on *success with escalation*; printed as observation either way |
| AX-X8 | `capsh --print` (if present), `cat /proc/self/status` piped to a grep for `CapEff` | `CapEff` is 0 (no-new-privileges + cap-drop ALL); skip-print if `capsh` absent |

## 9. Test-environment rules (all three in-process steps)

Each hostile module runs its core sweep **twice**: once with an explicit environment the test sets
(`HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` all under the module temp dir, umask
`002` — the sandbox's shape) and once cleared the way a plain host login has it (umask `022`, XDG
unset, `HOME` under temp still). A finding that flips between the two is an environment artifact and
gets reported as such, not papered over; a finding that holds in both is a component bug and the
component is fixed (step specs carry the fix-allowlist). The sweep's mode checks use explicit
`stat` comparisons, never inherited umask assumptions. Free ports everywhere
(`bind(("127.0.0.1", 0))`); the real home directory is never written — enforced by pointing `HOME`
into the temp dir in both modes. No site values: nothing reads `~/.config`, and
`hub/tests/test_anonymity.py`'s scan pattern runs over every file this slice adds.

## 10. Chain plan

Four steps, all `hard: true` (this whole slice is the gate of gates; step 4 also being last runs
the full both-suite gate anyway):

| step | module(s) added | owns |
| --- | --- | --- |
| a2x-1 | `broker/tests/test_a2x_broker_hostile.py` (+ the new shared `broker/tests/fakebin.py`, patterned on `util.py`'s sh-farm without rewriting it, and a `protocol._strings` fix) | AX-B*, F*, G*, C* |
| a2x-2 | `hub/tests/test_a2x_relay_hostile.py` | AX-R* |
| a2x-3 | `oc/tests/test_a2x_oc_hostile.py` | AX-P*, M* |
| a2x-4 | `tools/a2-hostile-live.py` + `tools/tests/test_a2_hostile_live.py` | the live layer + AX-X*/E*/S* definitions, unit-tested against fake docker |

Each step's verify: its own module(s) through `tools/run_tests.py`, the full `tools/run_tests.py`
(hard step), and the scope guard against the previous step's branch. Step 1 must not break
`broker/tests/test_protocol.py`'s or `test_server.py`'s existing green (`_strings` tightening stays
a `bad_request`-shape change only, no new code); steps 2–3 add tests without touching the component
unless one fails — a failing component test is fixed **in that same step** with the fix named in its
Contract section (this is the slice whose whole product is the fix-things rule).

## Owner questions

- [default pick] **BiDi/control fix in step 1 (AX-B7).** The a2-2a spec promised control/BiDi string
  refusal; `protocol._strings` implements only NUL/length/surrogate. This design reads the promise
  as binding and fixes the component (C0/C1 except `\t\n\r`, plus the directional Cf set).
  Alternative: mark the promise dead and let hostile argv rest on exec-time rules. **Pick: fix.**
- [default pick] **Newline is inert, not forbidden (AX-B6).** Task texts are multiline by design, so
  the suite asserts framing-inertness instead of refusal; "newline args" in the hostile list is
  satisfied by that. **Pick: inertness assertion.** (Alternatives considered: refuse `\n` in
  delegate/gh argv only — rejected, splits the protocol into per-op string rules for no gain.)
- [default pick] **One request per connection (AX-B12)** stays the contract; the pipelined second
  request therefore gets a silent close, mapped by the client to 69 — hostile-relevant because it
  means no request can read its predecessor's answer.
- [default pick] **Live script skips, never forces.** If a probe cannot run without changing state
  (AX-X7's mount probe on an engine that audits-writes), it prints `SKIP` and exits 0; the owner
  reads the list. No `--force-unsafe` flag.
- [default pick] **Step 1 owns `fakebin.py` extraction.** Steps 3–4 import it; if the extraction
  churns `util.py` too much for review comfort, the fallback is a new module only, leaving
  `util.py` untouched (**pick: new module only, no util.py rewrite** — amended from the table's
  wording above, and the Contracts below match this).
- [default pick] **Cutover ordering.** Step 4's real run happens once, after the owner starts two
  live projects A and B (the script refuses otherwise); this slice's gate never runs docker.
