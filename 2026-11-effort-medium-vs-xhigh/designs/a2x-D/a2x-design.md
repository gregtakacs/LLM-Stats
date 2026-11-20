# a2x — A2 step 8: the hostile acceptance suite for the per-project isolation boundary

Design for the acceptance step of A2. **No product code changes** — this step is the suite that
proves the boundary the previous steps built, plus one host-run cutover script. Where a test finds
a real defect, the fix belongs to the step whose tests target the broken component (Files owned
below), never to the test: *never weaken a test*.

The rulings that shape it (binding, quoted where they bind):

> **Ruling 24:** "a suite, not a page in the docs; it must actually run a broker and a hub."
> **Ruling 25:** the container layer is a script the worker cannot run in the sandbox; it must
> come with unit tests against a fake `docker`, and the worker states plainly that the live run
> is the owner's at cutover.
> **Ruling 26:** the in-process layer must use the **real broker over its real Unix socket**, the
> **real hub relay over HTTP**, and the **real planner/installer** (`oc/projects.py`,
> `oc/install.sh`) with temp dirs — hostile inputs, **no mocks of the component under test**;
> fakes only for docker/git/gh as PATH executables that record their argv.

The question the suite answers, in one line per layer: **can a session inside project A's
container, or a request wearing A's credentials at the hub, reach anything that belongs to B or
to the host?** Every case below is phrased as an attack and a promise.

## 1. The boundary under test

What the isolation rests on, and who enforces each part (all of it already built — this step
only attacks it):

| The promise | Enforced by | Where |
|---|---|---|
| A container holds no Docker socket, no host service socket, no other project's path | the planner's bind list — the *only* mounts are its own | `oc/projects.py:binds` (line 201; tested by `oc.tests.test_projects` / `test_projinstall`) |
| Egress goes only through the filtered proxy | the project network is `--internal`; the only route out is the egress container | `oc/projects.py:network_argv`/`egress_argv` (lines 447-466) |
| The OpenCode port is bound inside the network namespace, never on the host | the create argv carries no `-p`/`--publish` at all | `oc/projects.py:create_argv` (line 441) |
| The broker answers A's socket, for A, and never names B | per-socket config; `tasks.require_task` (`tasks.py:183`); refusals shaped by `protocol.answer_error` + `DETAIL` | `broker/server.py`, `broker/tasks.py`, `broker/protocol.py` |
| The relay reaches only the project named by the raw path segment | the byte-for-byte matcher + `classify` P2 | `hub/routes.py:_project_api` (line 197), `hub/routes.py:classify` (line 247) |
| Host-side git never runs project-steered config | the `--exec`/allow-list layer and the push pipeline's `FORCED_CONFIG` | `broker/git_push.py:34-42`, `broker/delegate_rules.py:40` |

The gap this step fills: every suite so far attacks **one component**. Nothing in the repo drives
the chain **hub → broker → child** or **planner → installer** with hostile input across component
seams, and nothing proves the container-level promises from the *outside* — that is what a hostile
session in A actually has: A's broker socket, A's mounts, A's network, A's credentials. Step 6's
`launcher/tests/test_a2a_hostile.py` covers the admin-session hostile matrix (33 cases); this
slice covers the project-container side of the same boundary.

## 2. Two layers, and why both

**Layer 1 — the in-process hostile suite (the gate).** The repo's own unittest style, run by
`python3 tools/run_tests.py`, so it protects every future change. The components under test are
real; the environment fakes are PATH executables (`docker`, `git`, `gh`) that record their argv
to a JSONL log. A test may import the planner and call it with a hostile spec; a test may not
import a *mocked* broker, hub or installer.

**Layer 2 — the live cutover script (`tools/a2-hostile-live.py`, which the owner runs once at
cutover against the real stack).** No sandbox can prove that the *real* Docker gave the *real*
container the planned network: `--internal` can be ignored by a runtime, a ULA can be routed, a
mount can be remounted rw, and a wrong-uid `docker exec` sees a 0700 dir anyway (the a2 spike
lesson — uid checks need an in-container probe). The script is the only artifact that can answer
"what does project A's container *actually* hold?" It must never change state (§7). The worker
unit-tests it against a fake `docker`; **the worker cannot run it for real — no Docker in the
sandbox (ruling 25)**; the orchestrator must not count an unrunnable live probe against the step.

## 3. Threat coverage (a2-design §10 and a2a-design §11, every row)

How to read this table: every threat row of both designs, the tests that already press it, and
what *this* slice adds. "adds" is the delta the new modules must earn — a case that would only
re-run existing coverage does not enter this suite (ruling 24's "the delta"). Case ids here are
the §5 cases; steps restate them with their own numbering.

| Threat row | Already covered by | a2x adds |
|---|---|---|
| prompt injection → its own reach only, not other projects, not the host (a2 §10 r1) | launcher suite (step 6); `oc.tests.test_sessions` | XB17 (broker cannot be steered into B's repo), P7 (egress is the only door), P4/P6 (the host is actually closed) |
| stolen Google session → everyday hub (a2 §10 r2) | `hub.tests.test_a2h_*` (gate + authz); admin = a2a step 6 | nothing new at the gate; XB1/XB18 keep broker reach gated on the socket; P1/P2 prove the boundary |
| session reads another project's secrets (a2 §10 r3) | `test_a2h_relay` X7 (credential per row); `test_projects` (mount refusals) | XO1/XO7 (A's planned bind list contains nothing of B), P6 (B's data dirs unreadable from inside A) |
| broker bug: argv or path injection = the new boundary (a2 §10 r4) | broker per-module suites; a2g-4 | the cross-component set XB3–XB9, XB11–XB13: hostile input as it arrives *through the socket protocol*, not the function |
| container escape, kernel (a2 §10 r5) | out of scope (the design says so) | out of scope; P7's SKIP line records the accepted-by-design row; kernel escape remains untested |
| stolen session opens/extends a project admin session (a2a §11 r1) | step 6, `test_a2h_routes` | none — a2a-10's step owns it; row here for completeness |
| restricted container plants host-run code: hooks/MCP/CLAUDE.md, OpenCode plugins, git hooks/fsmonitor/signature programs, planted `{project}-project` (a2a §11 r2) | step 6 (preflight, env off, absolute-path helper), a2a-10 | XB6 (the same steering keys smuggled through A's broker: `unsafe_config`, argv-level); XO7 (the bind list gives no host hook dir) |
| **hijacked project admin / hostile container acts outside its project** (a2a §11 r3) | step 6 covers the admin shell's residual; the container half is what A2's broker exists for | the whole suite: XB3–XB10, XA1–XA3, P4–P7 — the container's real doors, closed |
| hijacked admin acts on another project (a2a §11 r4) | step 6 (cgroup identity, per-project grants) | XB2/XB4/XB5 (`--repo`/cwd naming B at A's socket: `unknown_repo`, indistinguishable from absent), P2 (B's socket unreadable *and* unreachable from inside A) |
| container plants a label claiming another project (a2a §11 r5) | `test_service.py` label filters; step 6 | XB16: service argv carries broker-minted names only — proof from the fake docker's log; P6 |
| container log output attacks agent/terminal (a2a §11 r6) | step 6 (caps, byte-clean) | none new (broker chunk/split coverage: `test_server`/`test_client`) |
| container writes the admin folder / generated profiles (a2a §11 r7/r8) | step 6 (state dir 700, rebuild each start) | the planner half: XO7 (a container cannot mount the launcher's state dir at all) |
| **compose deploys a host takeover** (a2a §11 r9) | a2a-10's compose validator (its 33 cases) | none at the validator; XO8 at the *installer* seam: every refusal leaves zero `run`/`create` argv in the fake docker's log |
| allow-listed external network reaches other stacks (a2a §11 r10) | accepted with the allow-list | none — accepted; live P8 guards the accepted shape actually holds |
| container_name takeover of another project (a2a §11 r11) | a2a-10; XB16 | none new |
| reads/changes another project's secrets (a2a §11 r12) | step 6 (deny-by-name); relay X7 | P6 (the secrets root is not in A's mounts, provable from inside), XO1/XO7 |
| OpenCode container reads the secrets root (a2a §11 r13) | `test_projects.py` refusals; doctor | XO7 asserts A's plan against B's whole registry entry; P6 on the real mount table |
| compose actions race each other (a2a §11 r14) | step 6 | none new |
| config text injected via crafted names (a2a §11 r15) | `test_projects.py` (MOUNT_BAD_CHARS), routes X24 | XO3 planner seam; XR10/XR11 relay raw-path seam (never pre-decoded) |
| owner's user-level Claude settings widen a profile (a2a §11 r16) | a2a-8 doctor warning | none — admin-side, owned elsewhere |
| crafted project/member name reaches a path/unit/tmux (a2a §11 r17) | broker config, registry gates | XO3 (planner), XR1–XR6 (relay), XB18 (the client's socket pointer is not a permission), P2/P3 |
| forged request picks another project's member (a2a §11 r18) | `test_targets.py` | XB5 (same attack, cross-project, through the socket) |
| ended session's terminal stays reachable (a2a §11 r19) | step 6, hub 404 | none new |
| one project's admin acts on another's unit (a2a §11 r20) | step 6 hostile pairs | none new |
| work view credits a session to the wrong project (a2a §11 r21) | `test_work_join` + step 6 | none new |

The relay hostile table (a2h-design §10, X1–X25): every row except **X25** is already delivered
in `hub/tests/test_a2h_*.py` (X20's admin-origin half rides the `classify` table). X25 — the wake
race, two logins to one project, the second answered `no_login` → hub **409**, proven only
launcher-side today — is re-fought at the relay seam as **XR14** against the real `build_server`
(§5.2). The rest of the relay table is not re-typed: this suite takes the cross-component paths
and the container-reach threats that per-component suites structurally cannot see.

## 4. The fakes (layer 1)

Ruling 26 allows fakes **only** for docker/git/gh, and only as PATH executables. The repo's
`broker/tests/fakes/` already are exactly that, recording JSONL (`call_log`, `git_calls`,
`gh_calls`, `docker_calls`, `clear_calls` in `broker/tests/util.py`); the docker fake carries a
stateful world (`FAKE_DOCKER_STATE`: version / network inspect / ps / run -d / rm -f, refuses
duplicate names with 125 like real docker, stat's env-file modes at call time, and its
`forbidden()` reuses `broker.services`' own regexes so the fake cannot drift from the rule). The
`git` fake is a **recording pass-through** to real git — the allow-list must run against real
repos, not a stub. New modules import these; they add nothing to them. The hub layer reuses
`hub/tests/httputil.py`: the real `build_server` via `HubTestCase`/`start_hub`, a live
`FakeOpenCode` per project (its recorded `last`/`header()` is the assertion), `write_projects`,
`raw_request`. `oc.tests.test_projinstall`'s PATH-shim pattern (a Python `docker` on PATH that
records every argv to `shim.log` over a mutable JSON world, the installer run as a subprocess
with a scrubbed env) is reused for the installer seam — nothing may leak from the host env.
What a PATH fake *cannot* be: a unix socket pair, a listening TCP port, a real device node —
those stay layer 2 (§7).

## 5. The cases

Each case: the attack, the promise, the expected outcome by the real contract (cited), and the
assertion that the absent side-effect is what makes it a *pass*. "silent as absence" means the
answer must be indistinguishable from the resource not existing — no existence leak. Shared
fixture shape: two projects **alpha** (A) and **beta** (B); B's facts are canary values
(`/srv/{project}/repos/beta`, `BETA-SECRET`); every cross-project refusal is additionally asserted
to contain **no substring of B's identity** — "did not name B" as a mechanical check. Every
module sets `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` into its own temp dir
and uses explicit modes everywhere (the host umask here is 002 — the a2a-10 worker rule), and
free ports only (`bind(("127.0.0.1", 0))`).

### 5.1 Broker through the socket (`broker/tests/test_a2x_broker_hostile.py` — step 1)

| # | Attack | Promise | Expected (real contract) | Absent side-effect |
|---|---|---|---|---|
| XB1 | request over **B's** socket naming A's task/repo | the socket *is* the identity | `unknown_task` / `unknown_repo`, silent as absence (`tasks.require_task`) | zero fake-delegate calls; audit names only B |
| XB2 | A's socket, `--repo beta`, or cwd = B's worktree root | cross-project is absence | `unknown_repo` (`test_targets`), cwd → `outside_project` (`paths.child_cwd`) | nothing ran; refusal names no path (`protocol.refusal`) |
| XB3 | `--repo /srv/{project}/repos/beta` (absolute host path) | path-shaped repo never reaches the resolver | `unknown_repo` (`paths.py:134`, resolved-path compare) | zero calls |
| XB4 | `--repo beta` over **B's** socket — the control | the boundary is the socket, not the string | runs (fake records it) | — |
| XB5 | task-id field = B's id over A's socket | foreign task = unknown task | `unknown_task`, byte-identical to a never-heard id | no audit trace of B's id (the a2g-4 rule) |
| XB6 | git config `core.fsmonitor` / `core.hooksPath` / `filter.git.*.clean` / `diff.external` / `credential.helper` planted in **A's own** repo config and named toward B's | steering keys never run host-side | `unsafe_config` (`repocheck.DANGEROUS_KEY`, `repocheck.py:31-34`); `credential.helper` is forced empty on pushes, not refused (`git_push.FORCED_CONFIG`, `git_push.py:34-42`); the XB6 test asserts which spelling the contract covers and reports `diff.external` as a FINDING if the regex misses it | the fake git records no such subprocess; refusal names no path |
| XB7 | cwd walks out: `..`, symlink member → `/`, planted swap after check, hard link into B, FIFO/device special file | realpath decides, not the string | `outside_project` / `not_a_file` (`paths.child_cwd` `paths.py:104`, `read_inside` `paths.py:172`) | nothing read, nothing ran |
| XB8 | read a spec through a symlink swapped **after** open | the fd recheck | `not_a_file`; the original survives unread (`paths.read_inside` (`paths.py:172`)) | no answer body |
| XB9 | transport poison: NUL, newline, bidi/RTL inside argv; 10 000-char arg; 65 args; trailing newline past `^…$`; non-finite/huge JSON numbers; duplicate keys; bytes after the newline | the frame parser refuses before semantics | `bad_request` / `too_large` (`protocol.parse_line`; MAX_LINE=262144, MAX_ARGV=64, MAX_ARG=200) — one line then EOF (`server` one-connection handler (`server.py:302`)) | child never spawned; connection dead |
| XB10 | 50 concurrent connections on one socket, then 50 concurrent in-flight requests | accept-list + `busy`, never an unservable half-state | connect succeeds then `busy` (one line, client exit 125 — the a2g-4 accepted form); no traceback; socket healthy after | zero calls for refused ones |
| XB11 | half-written request + close; truncated stream mid-line | the line rule kills it | connection closed, no answer, no crash (test_server precedent) | — |
| XB12 | one malformed line among 20 well-formed ones | poison does not poison the neighbour | each connection answered on its own terms | — |
| XB13 | oversized request (256 KiB + 1); oversized `report` body | MAX_LINE / `read_inside` `too_big` | `too_large` without reading the rest (`server.py:582`) | connection closed |
| XB14 | `push` with ref `refs/remotes/origin/x`, `..`, `refs/../x`, `main\nevil` | REF_RE decides (`git_push.py:30`) | `bad_ref`; the fake git sees no push argv | audit records the refusal only |
| XB15 | `push` with `repo` = `https://x.invalid/`; env-injected `GIT_SSH_COMMAND` | remote must be the github pair; env is the broker's | `bad_remote`/`not_github` (`git_push` request checks); recorded env carries only `FORCED_CONFIG` + the runner env (`git_push.py:34-42`) | zero git calls |
| XB16 | service `up` with argv naming B's network / an alias / `oc-beta` | broker-minted names only | `refused_argv` (`services.check_argv` `services.py:116`, `FORBIDDEN_FLAGS`/`FORBIDDEN_WORDS` `services.py:64-66`) or `no_network` | fake docker world byte-identical |
| XB17 | `delegate --repo` aimed at B's repo path; `git --git-dir=<B>`; bare `-C`; `--exec-path`; env `GIT_DIR`/`GIT_WORK_TREE`/`GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` | argv layer rejects host-steering before the resolver | refused at the layer (`delegate_rules.py:40,422`); recorded env never carries the caller's | zero calls |
| XB18 | client subprocess with `PROJECT_BROKER_SOCK` = B's socket path | the env var is a pointer, not a permission | identical `unknown_task` answers as over B's socket (`client.py:28,62`) | zero calls |

### 5.2 Hub relay, seam with the socket (`hub/tests/test_a2x_relay_hostile.py` — step 2)

| # | Attack | Promise | Expected | Absent side-effect |
|---|---|---|---|---|
| XR1 | `GET /p/B/api/x` carrying **A's** project cookie | the raw segment decides the target; the cookie must match it | 401 (`routes._project_api`, byte-for-byte, `routes.py:197-208`) | B's FakeOpenCode records nothing |
| XR2 | A's credential over `/p/A/` while B's fake answers with its own password | credentials are per-project, never mixed | relay sends **A's** password only (`proxy.request_headers_for`, `proxy.py:325`) | B's fake never dialed |
| XR3 | `/p/%2e%2e/`, `/p/A%2fB/`, `/p/A%252fB/`, other double/triple encodings | names match on **raw bytes**, one normalization, never recursive decode | 404 (`_project_api`, `routes.py:197`); no percent-decode in the match | no upstream dialed |
| XR4 | reserved names (`broker`, `hub`, `new-session`, … — `RESERVED_PROJECT_NAMES`, `broker/config.py:55`) and case spellings (`/p/BETA`, `/p/Beta`), trailing dot/slash (`/p/A./`, `/p/A//`) | registry refuses reserved on load; the relay 404s every miss | 404 at the relay; a reserved name could never have been configured | — |
| XR5 | WS upgrade at `/p/B/…` with A's cookie, and with none | gate before dial (gate before dial: `hub/routes.py` doc, gate step 1) | 401 before any dial | B fake `ws_handshakes == 0` |
| XR6 | headers claiming another project/identity: `X-Forwarded-Host: b.internal`, `Forwarded`, `Host: beta.internal`, `X-Target: B`, `X-Original-URL` | the hub overwrites `X-Forwarded-Proto`/`-Host` with its own values (`proxy.py:363-366`); nothing else forwarded | target's `last` shows hub values only | — |
| XR7 | client sends `Cookie: auth_token=<B's password>` | `auth_token` never forwarded (`PROJECT_DROP`, `proxy.py:102`) | target sees only hub-minted auth | — |
| XR8 | `GET /p/A/..%2f..%2fapi/x` (dot-segments *inside* the target part) | the target is forwarded verbatim (`routes.py:325` `_forward_target`, row P6) — it stays inside A's container's own reach | relayed byte-for-byte to A's fake only | B fake quiet |
| XR9 | oversize: declared body > the row cap; a ~2 MiB request line; 200 header lines | caps answer, never crash | 413 on the declared body (a2h X12 precedent); the line/headers close the connection | no upstream dialed |
| XR10 | newline/CR inside a path or header value (smuggling shape), obs-fold, `Transfer-Encoding: chunked, chunked` | the framing rules of a2h X11 hold at the projects door too | 400/501, connection closed | nothing forwarded |
| XR11 | bidi/RTL, NUL and control percent-encodings inside the segment | raw-bytes match | 404 | — |
| XR12 | 50 concurrent relayed requests mixing A and B, one bad among good | per-request isolation | good ones complete; the bad one answered alone; upstream `last` never cross-contaminated | — |
| XR13 | half-open: send head, stall, close; then reuse the socket for a second request | one request per connection (`handle_one_request` analog) | first times out/closes; second not answered on that connection | — |
| XR14 | **X25 at the hub:** two concurrent project logins for A through the real relay while the launcher stub serializes them | second is `no_login`, and no wake happens on refusal | 409 (`ERROR_STATUS`, `hub/adminapi.py:50-55`) | exactly one start line reaches the launcher stub |
| XR15 | cross-seam control: the *same* hostile name (say `..%2fB`) at all three consumers — relay 404, broker config `ConfigError`, planner `PlanError` | one name, three doors, all shut, each in its own shape | as cited; none echoes the value | — |

### 5.3 Planner, installer, migration (`oc/tests/test_a2x_planner_hostile.py` — step 3)

| # | Attack | Promise | Expected | Absent side-effect |
|---|---|---|---|---|
| XO1 | a registry where A's members include `/`, `$HOME`, `/usr`, B's dir, the Docker socket, `/run/user/$UID`, the secrets root, the registry dir itself | the container's reach is its own dirs; the overlap refusals live at the installer/preflight door (`install.sh`, `projinstall`) | the installer's refusal (test_install/test_projinstall matrix precedent); the planner's own refusals (`PlanError` key `mount`, `projects.py:172-184`) cover what reaches it | no create argv exists |
| XO2 | a member path reached through a **planted symlink** into B's dir | bind sources are real dirs; a link is refused (`mounts.problems`, planner check) | refused; and on the installer path nothing is written | zero `run` argv in the fake docker's log |
| XO3 | hostile project names at every consumer: `..`, `.`, `x/y`, backslash+newline, NUL, bidi, 10 000 chars, `web` vs `web-app` (the prefix trap), a case-spelling of an existing name, a reserved name | one rule at every consumer, refusal without echoing | hub registry `ProjectError` (`hub/projects.py:41` `SEGMENT_RE`), broker `ConfigError` (`broker/config.py:55,319`), planner `PlanError` (`projects.<P>`), relay 404 | — |
| XO4 | `secret_file` = the Docker socket / `/etc/passwd` / a 0640 file / relative / a symlink | shape at the planner (`PlanError` key `secret-file`, `projects.py:241`); the **mode** rule is the installer's (`install.sh`, the 0640 refusal matrix in `test_install`) | the refusal at the door that owns the rule | — |
| XO5 | planner inputs docker would take wrongly: subnet `/29` or IPv6 or `0.0.0.0`, container name > 127, image `a b`, egress name docker would reject, empty image, daemon-placeholder name | the planner refuses before argv exists | `PlanError` (the `network_argv`/`create_argv` matrix, `test_projects` precedent) | — |
| XO6 | scan A's full create/network/egress argv for `--device`, `--privileged`, `-p`, `--publish`, `-v /:/host`, `--pid=host`, `--net=host`, `--security-opt`, `--group-add`, and any host path that is not A's | the generated argv contains none of them (`create_argv`: no publish at all) | assertion on the returned argv **and** on the fake docker's recorded call | zero mounts outside A; no host path anywhere (`binds`) |
| XO7 | host-hook reach: `/etc`, `~/.ssh`, `~/.claude`, `~/.config`, `~/.gitconfig`, the Docker socket, `/run/user/$UID`, the launcher's state dir must appear in **no** bind/argv/env entry of A's plan | mounts are A's dirs or nothing; the admin folder is never mountable (a2a §11 r7) | set-diff assertion over the whole plan | — |
| XO8 | installer (`oc/install.sh projects`) driven with: a policy that denies; a registry changed mid-run; a planted symlink at a worktree root; a foreign `{project}-oc-*` container in the shim's world | refuse **before** create; never touch a foreign container | the projinstall refusal path (`projinstall.py` phases/`Failure`); the recorded shim log has no `rm`/`create` for the foreign id and no partial create for the refused one | every generated file passes `site_values_in` (the anonymity gate's helper) |
| XO9 | installer with A's secret file at 0640; provider key written as a raw value instead of a secret file | exact mode or stop; a provider key must be a secret file | the installer's refusal line (`test_install` matrix), nonzero exit | no password printed anywhere |
| XI1 | migration import fed hostile session JSON: path escapes, `..` titles, absolute-path fields, a planted `cwd` naming B, NUL/newline/bidi ids, > `MAX_SOURCE_BYTES`, > `MAX_PAYLOAD_BYTES`, duplicate ids, deep recursion, non-UTF-8 | §9's rule: a session lands **only** in its own project's store, or the run is refused; hostile *content* can never steer a *path* | exit 1/2 with the reason (reasons from `migrate.REASONS`, `migrate.py:51-53`); a *valid* session whose title is hostile imports into its own store only (title is data, never a path); session content never echoed (`MAX_*`) | the injected FakeDocker's import argv names A's id only; B's store untouched |
| XI2 | migration where the destination container is missing / unlabelled / labelled to **another** project | never a guess | exit-2 reasons (`no_container`, probe mismatch), nothing imported | zero import calls |
| XI3 | all of XI1 with `--dry-run` | nothing changes, ever | the dry-run contract (`test_migrate` precedent) | the world file byte-identical |

### 5.4 The accept / network boundary (`hub/tests/test_a2x_accept.py` — step 2)

The hub's source guard exists (`proxy.address_is_refused`, `accept_is_refused` at
`hub/__main__.py:154,216` (`address_is_refused`), the `test_a2h_accept` precedent). The delta here is the
**projects-mode** shape:

| # | Attack | Promise | Expected |
|---|---|---|---|
| XA1 | connect to the hub's port **from within alpha's planned subnet** (bind to the loopback alias the registry plans; else the `from_fd` seam) with valid admin cookies | the hub answers only its own networks | zero bytes back, `FakeVerifier` never hears (the `test_a2h_accept` matrix replayed for projects mode) |
| XA2 | a request with **no** `X-Forwarded-For` claiming to be a project | no header is believed | treated as its peer address, refused |
| XA3 | `X-Forwarded-For: 127.0.0.1` on every row | forwarded-for is never consulted for the accept decision (`hub/__main__.py:154`: the peer address decides; no header is consulted) | accept unchanged by the header |

## 6. Layer 2 — `tools/a2-hostile-live.py` (step 4)

The host-side cutover probe, stdlib only, run by the owner at cutover with:

    sudo docker exec -u <container-owner-uid> {project}-oc-alpha python3 - \
        --project alpha --other beta < tools/a2-hostile-live.py

Design choice: **self-contained, injected via stdin** — not baked into the image; the script
changes with the threat model, the image does not (the image has python3 because the broker
lives in it, `oc/Dockerfile`). An optional `--via-docker` mode wraps probes in `docker exec`
for one-command use; the script performs no docker at all when reached by stdin. Contract:

- Output: one line per probe, `PASS <id> <what was proven>` or `FAIL <id> <observed>`; a final
  `SUMMARY pass=N fail=N`; **exit 0 iff every probe line is PASS**; non-zero, and no traceback
  on a single-probe error — a probe that cannot run reports FAIL, never crashes the run. The
  format is `livecheck.sh`'s, so its replay-test idea applies.
- **Never changes state.** Read/connect/refused-request only: it never writes outside the
  container's own `/tmp` scratch (removed at exit), never creates or removes a
  container/network/volume, never restarts, never sends a push/`up`/`import`. A probe that
  would need a state change to run does not live in the script — it lives in the runbook (§8)
  marked as a manual owner step.
- Refuses to run without `--project A --other B` where **both** are present in the registry
  visible to the script (`/run/{project}/projects.json` or `--registry <path>`); bad args → exit
  2, no probes run. `--dry-run` lists probes, exits 0.

Probes (all run *inside* A's container, so they test exactly the reach a hijacked session has):

| # | Probe | Expected |
|---|---|---|
| P1 | the OpenCode port listens on loopback **inside the netns** and answers 401 unauthenticated; nothing on the host address (no `-p` was ever given) | PASS = reachable only as designed |
| P2 | `/run/{project}/sock/<B>/broker.sock`: `stat` → permission denied or ENOENT; `connect` → refused | PASS = A cannot read or reach B's socket |
| P3 | `/run/{project}/sock/<A>/broker.sock` exists, is A's, mode 0600, and `client … list` answers on it | PASS = the one socket A holds is A's |
| P4 | `/var/run/docker.sock`, the host systemd bus, `/run/user/1000`: connect/`stat` refused | PASS = no host service socket |
| P5 | the launcher and helper sockets (the paths of the §1 table): refused | PASS |
| P6 | host `~/.ssh`, `/etc/shadow`, the secrets root, `/home`: unreadable; the mount table (`/proc/self/mountinfo`) shows no rw bind outside A's own subtree and no path of B anywhere | PASS = the mount table is A's dirs or nothing |
| P7 | egress boundary: direct connects to two LAN targets (B's planned OpenCode port on B's container IP; an arbitrary closed port) time out or are refused, never succeed; through the proxy, a non-allow-listed host is refused | PASS = A cannot touch the LAN; the accepted external-network row (a2a §11 r10) is **not** probed — allowed by design, marked SKIP in the runbook |
| P8 | env hygiene: `os.environ` names match the planned env table — no `*_TOKEN`, no GitHub token, no provider keys, by name | PASS = the token never enters the container |
| P9 | the GitHub token canary: A's own env, `/proc/self/environ`, and a broker `list` answer searched for the sentinel — absent | PASS |

Unit tests (`tools/tests/test_a2_hostile_live.py`): the script's pure logic (arg parsing, probe
list, PASS/FAIL/SUMMARY emitter, exit codes) is importable, and the `--via-docker` path runs the
whole script against a **fake `docker`** on PATH (the `test_projinstall` shim pattern) covering:
all-PASS → exit 0; one injected FAIL (the fake says a socket answered) → FAIL line + exit
non-zero; the fake `docker` missing → dependency FAIL reported, no traceback; bad args (missing
`--project`, a `--other` not in the registry) → exit 2; `--dry-run` → probe list, exit 0. The
worker **cannot run the live probes here** — no Docker in the sandbox, ruling 25 — and says so
in its report; the runbook is the owner's cutover checklist.

## 7. The runbook

`docs/a2x-cutover.md`: the owner-run sequence — full gate green → P1–P9 for each project pair →
the two manual spike-style checks that *do* change state (stop A's container and confirm
`docker port` is empty; `findmnt` from the host side for one container) → where to keep the
evidence. Fenced commands must be valid bash after placeholder substitution, the
`oc/tests/test_acceptance.py` precedent.

## 8. Steps (4) and files owned

| Step | File(s) owned | Fixes allowed (only if a case finds a defect) |
|---|---|---|
| a2x-1 | `broker/tests/test_a2x_broker_hostile.py` | `broker/*`, narrowest change |
| a2x-2 | `hub/tests/test_a2x_relay_hostile.py`, `hub/tests/test_a2x_accept.py` | `hub/*` |
| a2x-3 | `oc/tests/test_a2x_planner_hostile.py` | `oc/*` |
| a2x-4 | `tools/a2-hostile-live.py`, `tools/tests/test_a2_hostile_live.py`, `docs/a2x-cutover.md` | none (script bugs are the step's own fix) |

Every step `"hard": true`; every verify ends with the full repo gate
(`python3 tools/run_tests.py`, both suites, a2h-chain.json style: log to
`${DELEGATE_EVIDENCE_DIR:-/tmp}/verify-<step>.log`, assert one `ok <module>` line per expected
module and `! grep -qE '^FAIL +|^not ok'`) and the scope guard (`git diff --name-only <base>` ⊆
declared scope). Fix files belong to the step whose tests target them, so a defect never
orphaned a diff. Step 4, the last of the chain, runs the full gate per the test policy.

A defect a test finds is fixed in the **component**, with the narrowest change that satisfies
the existing contract; the commit records the finding like `oc/tests/test_acceptance.py`'s
FINDING precedent. If fixing would change a contract (an error code, a refusal shape), the step
stops and reports — a contract change is the orchestrator's call, not a hostile suite's.

## Owner questions

1. **Live-script delivery.** Baked into the image, or injected via stdin at the run?
   **Pick: injected** — the image stays static, the script stays hot-updatable, `--via-docker`
   keeps the one-command shape. Baking is one Dockerfile line away if the owner prefers it.
2. **How the script learns the pair.** Registry read from the `/run/{project}` mount, or every
   path passed as a flag? **Pick: registry first (`--registry` override, default
   `/run/{project}/projects.json`), flags only for `--project/--other`.**
3. **Concurrency target.** The task says 50 concurrent; the broker caps connections at
   MAX_CONNECTIONS. **Pick: connect-burst 50 with `busy` as the protocol-visible answer (client
   exit 125), and in-flight concurrency asserted at the configured cap** — measuring the kernel's
   accept backlog would test Linux, not the broker.
4. **Subnet-alias binds in CI.** Rootless CI cannot bind `10.99.0.x`. **Pick: attempt the real
   bind, fall back to the `from_fd` seam assertion** (both shapes exist in `test_a2h_accept.py`),
   so the test never silently degrades on a capable host.
5. **Step count.** Four steps, per the chain task's 2–5. **Pick: 4** — the three in-process
   layers split by component (each its own fix-scope), the live layer standalone.
