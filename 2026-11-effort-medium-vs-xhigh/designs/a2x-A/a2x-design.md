# A2x — design: the hostile acceptance suite (step 8, two layers)

Design of record for chain `a2x`. Splits A2 step 8 ("hostile: cross-project, egress escape,
resource limits, TOCTOU, secrets, injection — test-first, fix what it finds") into four steps.
Ruling 26 (a2-design.md §8) decides the shape: the suite lives in **two layers**.

- **Layer 1 — the gate layer (steps 1–3).** In-process hostile tests over the real decision code
  (`broker/`, `oc/projects.py`, `hub/routes.py`, `launcher/oc.py`), driven through the **fake
  executables on PATH** already in `broker/tests/fakes/`. These run under
  `python3 tools/run_tests.py` on every commit and are the CI signal.
- **Layer 2 — the container layer (step 4).** One host script, `tools/a2-hostile-live.py`, that
  runs the same probes against **real running containers**, read-only, at cutover only. Ruling 26
  is explicit that the sandbox cannot run it and nobody should pretend it passed: it is
  stdlib-only, every probe is read-only, and it is unit-tested in-process against a fake `docker`
  executable so the gate proves its harness — while `LIVE PROBE RUN: NOT VERIFIED` stays in every
  report until the owner runs it.

## Ground rules (all four steps)

- **Rigs, not mocks.** A refusal is only proven when the test can show the side effect did *not*
  happen. The fakes record everything (`broker/tests/util.py`: `call_log`, `docker_calls`,
  `gh_calls`, `git_calls`; the fake `docker` keeps a JSON world with 0600 state). Every hostile
  case asserts both halves: the documented error shape **and** the absent side effect. The fakes
  are the harness's boundary, not the component under test: never fake or patch the code a case
  is about (no mocking `validate`, `build_plan`, `route`, `apply`).
- **Error shapes come from the code, not from the test's mood.** Each case cites the file that
  documents its refusal (`broker/protocol.py` `DETAIL`, `oc/projects.py` `PlanError`,
  `hub/routes.py`, `launcher/oc.py` `ActionError`). Expected shapes are pinned **at the documented
  granularity** — the exact code and message where the contract fixes one (e.g.
  `unsafe_config: the repository config asks the broker to run something host-side`), the
  documented equivalence class where it fixes a class (e.g. anything the `^…$` regexes reject is
  `bad_request`). A fix must not "adjust" a documented shape to make a case pass, and a worker
  must not loosen a test to make it pass either.
- **Fix policy.** A case that fails because of a real bug → the step fixes the **component** and
  commits test+fix together. Each step's Files owned therefore names the component files its
  cases may reach (reviewers: a fix that touches anything else is out of scope). This is
  handoff §3's rule — workers never widen a step's scope, and never edit a test to pass.
- **Home isolation.** Every test that reads or writes `$HOME`/XDG sets `HOME`,
  `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` into its own `tempfile.TemporaryDirectory`
  — real home is never touched — and passes directory modes explicitly (host umask is 002;
  handoff §2). No site values anywhere: `hub/tests/test_anonymity.py` hashes the suite.
- **Git.** Workers commit; never merge, rebase, stash, or checkout (handoff §3).

## Threat-model axes A2 step 8 names, and who owns them

A2 step 8's list is a superset check-off over the per-chain threat tables (a2-design.md §10,
a2a-design.md §11, a2h-design.md §10 X1–X25). Chains a2g, a2a, a2h, a2i, a2k already *implemented*
most rows. A2x re-attacks every row **compositionally** — one session, cross-cutting vectors,
fakes watching every side channel — and its new value is the gaps §coverage lists. A row is only
"done" when a2x names the existing test, the gap, and the step that closes it.

## Step 1 — broker write-path hostile (a2x-1)

The write path: `--repo` resolution, push-config scanning under TOCTOU, git-config host-execution
vectors, wire framing on the live socket, and concurrency. Existing coverage is deep
(`broker/tests/test_paths.py`, `test_server.py`, `test_protocol.py`, `test_push.py`,
`test_delegate_write.py`, `test_groups_hostile.py`); the gaps this step closes:

1. **`--repo` cross-project through the live client.** The in-process refusals exist
   (`test_paths.py::test_with_repo_is_the_only_way_a_context_gets_its_target`,
   `test_groups_hostile.py::test_a_repo_field_that_is_not_a_member_name_refuses_the_request_itself`)
   and one subprocess case exists for a different vector
   (`test_the_client_itself_refuses_a_view_with_the_socket_s_own_exit_code` runs
   `broker/client.py` under `sys.executable`).
   Not covered: a *real child process* (`broker/bin/request`, talking to A's own socket) naming
   B's repo while A's `PROJECT_TARGETS` is spoofed to list B — proving targets come from config,
   never from the peer (contract §6.6 ruling 16; a2-design §10 "A's container pushes B's repo",
   "Container spoofs PROJECT_PROJECT"). Expected: client exits 125, stderr exactly
   `broker: unknown repository (unknown_repo)`; `fx.git_calls()` shows no push. A smuggled
   `targets` key in the request JSON is `bad_request` (extra_key) end-to-end, not just at parse.
2. **Hard link into B.** `paths.read_inside` refuses symlinks, non-regular names and anything
   whose `real()` lands outside, and re-checks through the descriptor — but a plain *hard link
   to a file under B's repo*, planted inside A (same filesystem), is a regular file whose name
   is inside A: every existing check passes and the read follows the shared inode into B's
   content. No existing test plants one. Fix: after the `S_ISREG` lstat check, refuse
   `known.st_nlink > 1` with `not_a_file` (same class as the symlink refusal: the name does not
   exclusively name one plain file inside).
   Asserted both halves: refusal + B's content never in the answer bytes.
3. **TOCTOU swap of `.git` for a `--repo` target during push.** `test_delegate_write.py` swaps
   the *request spec file* mid-chain (`test_a_request_file_cannot_be_swapped_after_the_check`)
   and `test_push.py` proves the sha-not-branch discipline. Unproven: swapping the whole `.git`
   directory of the `--repo` target between the pre-push re-check and the subprocess — the chain
   must answer `unsafe_config` and `fx.git_calls()` must contain no `push` for that target.
4. **git config keys that would run host-side.** `core.fsmonitor`, `core.hooksPath`,
   `filter.<n>.clean`, `diff.external`, `credential.helper`. Push-side refusal covered
   (`test_push.py::test_a_key_the_project_can_write_is_refused_whatever_it_is`, HARD keys);
   delegate covers fsmonitor/hooksPath. New: (a) delegate refusal for **all four** hard flags on
   a push-chain target, each with its exact documented sentence; (b) `filter.*`/`diff.external`
   alone must NOT block a plain read (they are not HARD_CONFIG_KEYS — pinning this keeps a future
   "block everything" fix from breaking the contract); (c) the composition around the host-side
   git subprocess: `runner.GIT_ENV` (`broker/runner.py:182`) pins `GIT_CONFIG_NOSYSTEM=1`,
   `GIT_TERMINAL_PROMPT=0`, `GIT_ASKPASS=/bin/false`, and `git_push.FORCED_CONFIG` masks the
   dangerous keys with `-c` arguments (highest precedence, so a *user-global* config's answers
   for those keys never win) — **assert both through the fake git's recorded env and argv**, not
   by reading source; and probe the remainder: a host-executing key that slips past both during
   a push (an `include.path` pulling something outside the FORCED list) is the hole — fix by
   adding `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` `/dev/null` pins to `GIT_ENV`;
5. **Wire framing on the live socket.** Parse-level coverage exists in `test_protocol.py` (NUL,
   newline, 65k+ strings, NaN/Infinity, duplicate keys, nesting, non-UTF8). End-to-end gaps:
   bidi/zero-width payload and a 10 000-char single argument survive the real socket round-trip
   as exactly one `bad_request` line with the echo truncated to 200 chars (`protocol.MAX_ARG`,
   `Refusal.arg_echo`),
   and the audit carries no copy beyond it; a `ref` of `main\n` refuses in the documented class
   with the fake git recording nothing; **half-written request then close** kills nothing (the
   connection dies silently, the socket still serves the next request); **50 concurrent
   connections** with the backlog cap 8 (`test_server.py` proves the 9th→busy): every one of the
   50 gets exactly one answer (`ok` or `busy`) or a clean close, the server survives, and refused
   peers start no child; **one malformed among 49 valid** in the §6.6-batch shape: #17 of 50 gets
   one refusal line, the rest complete normally.
6. **Secrets never in what the broker writes.** A refused push whose remote URL carries a
   token-shaped secret: the log (`test_config.py` redaction) *and* the audit copy stay redacted,
   asserted through the composition this step lands.

## Step 2 — install plan, migration, egress (a2x-2)

The planner (`oc/projects.py::validate`/`build_plan`), the installer (`oc/projinstall.py`),
migration (`oc/migrate.py` + `oc/install.sh`), and the egress posture. Gaps:

1. **Malicious config → plan refusals** (each asserts `PlanError.key` exactly, and zero `docker`
   calls on PATH through the fake): a mount whose source is a symlink planted under the projects
   root (the planner must not follow it); a secret file that is a symlink → `secret-file`
   (refuse, do not read through); a providers file that is a symlink → `providers-file`; a
   project named exactly a `RESERVED_PROJECT_NAMES` member → `projects.<P>` (the planner
   enforces the broker's set so hub routes can't be shadowed — ruling 8's other half); a
   `model_names` entry with a space or an allow entry `*` / `host:443` → refused by the host
   rules (`pin_hosts`/`egress_argv`); an image reference that is not a usable `name:tag` (space,
   shell metacharacters, missing tag, `--` prefix) → the `_image_or_refuse` sentence
   (`oc/projects.py:332`). Individual units exist
   (`oc/tests/test_projects.py`); the gap is the *hostile values* through
   `validate`+`build_plan` composed.
2. **Double-planted links at apply.** `test_projinstall.py` proves a planted symlink at the
   worktree root, and at a home mount point, each alone writes nothing. New: both planted
   simultaneously → apply exits non-zero naming a deterministic first refusal, and neither
   link's true target was written (checked through the real inode).
3. **Migration hostile session export (a2-design §9).** The shared container is untrusted input:
   handcraft what it answers. Each case drives `run_main` with an injected `run` recorder and
   pins a documented `REASONS` member (`oc/migrate.py:51`) plus the absent side effect:
   (a) hostile id/title/directory fields (control chars, newline, `..`, leading `-`, 10 000 chars)
   — the docker exec argv stays an argv array (the recorder shows every field as one list
   element, no shell), and nothing on the host outside the 0600 report file changes;
   (b) a source answer that is not JSON, carries NaN, or exceeds `MAX_SOURCE_BYTES` →
   `too_large`/`export_failed` for that session only, the run carries the others;
   (c) message-count mismatch → `verify_failed`, and the recorder proves **no delete-shaped
   exec ever ran** (the no-delete rule of §9, composition-level); (d) `directory` matching no
   registry project → `not_selected`/`parent_missing` class; (e) a session the destination
   already has → `existed`, not a re-import (idempotency at the documented granularity).
4. **Egress LAN side, in-process.** The planner must never hand a container a LAN pin:
   `build_plan` with the resolver mocked to return `10.0.0.5` / `127.0.0.1` / `169.254.169.254`
   yields argv with **no** `--add-host` line carrying an RFC1918/loopback/link-local address
   (ruling: only public IPs get pinned; `test_projects.py` has the single-host versions — the
   composition through `build_plan` and the fake docker's recorded create argv is new). The
   runtime rule (proxy re-checks the connect IP) is A2E's; a2x pins only that the plan forces
   `HTTPS_PROXY` to the egress container and `NO_PROXY` to localhost-only whatever the config
   claims, so a config cannot route the container around its own proxy.

## Step 3 — hub relay + launcher (a2x-3)

1. **Cross-project relay with A's credentials.** The accept layer already answers X1–X5
   (`test_a2h_relay.py`: dot segments 400, encoded slash 404, spellings incl. `/p/Alpha/` 404,
   unconfigured names 404) and X7 (a foreign credential buys nothing). Remaining router gaps,
   each asserted with the fake upstream recording zero calls: `/p/alpha./` (trailing dot must
   NOT normalize into `/p/alpha/`); double-encoded `/p/%252e%252e/`; every member of
   `RESERVED_PROJECT_NAMES` on the project row in both cases (`/p/api/…`, `/p/p/…`, `/p/Auth/…`)
   — never served as a project, whatever the registry says; a WebSocket upgrade at
   `/p/<foreign>/api/pty/x/connect` with *valid other-project* credentials answers 404 before any
   handshake bytes; and a hand-planted registry entry named `Api` (written straight to
   `projects.json`, bypassing the broker) still cannot acquire a project row — the belt half of
   ruling 8.
2. **Reserved-name parity, both directions.** `broker/tests/test_config.py`
   `test_the_reserved_names_are_exactly_the_hubs_own_routes` pins broker == hub as sets. New: the
   broker's guard is *case-insensitive at config write* (`config.py:319`) so `Api` never enters
   the registry, and the hub's router is byte-exact — a2x pins the composed statement: for every
   reserved word and every case variant, no accepted broker config names it, and no route serves
   it. (The daemon has no reserved set by design: names reach the hub only through the broker;
   this step pins that reasoning with the `Api`-planted-registry case above.)
3. **Launcher `oc` target — composition gaps.** `test_oc.py` covers each single hostile state
   richly (bind source that is a link / gone, wrong label, missing container, world-readable
   registry, borrowed name — lines 261–342). The unproven composition: **two hostile states at
   once** — bind source planted as a symlink AND the container wearing another project's label —
   must refuse in a deterministic order (the mount check first, `unsafe_mount`), audit exactly one
   refusal naming the caller, and the recording docker must show **zero** `start`. Plus the
   registry read once per action: a registry replaced between two calls in one action must not be
   consulted twice (no TOCTOU window between name-lookup and start).

## Step 4 — container probes (`tools/a2-hostile-live.py`)

Host-runnable, stdlib-only, single file in `tools/`, gate tests in `tools/tests/` (the `suites`
tuple in `tools/run_tests.py` already includes `tools`). CLI:
`python3 tools/a2-hostile-live.py --project A --other B [--dry-run] [--socket PATH]
[--require-hub] [--allow-mount-home] [--allow-mount-run-user]`. Both project names required —
"cross-project probes need a second real project to point at" (ruling 26). Refuses with exit 2
(`not-running`) before any exec unless `docker ps` shows the containers for both projects.

**Never changes state** — enforced by structure: exactly two effect primitives, `docker inspect`
and `docker exec <container> <argv>`, where argv is drawn from a fixed allow-list of read-only
probes (`ls`, `stat`, `readlink`, `test -e`, `env`, plus `broker/bin/request` with hostile argvs
that the *broker* refuses, plus one `python3 -c` connect helper). The unit tests assert every
argv the fake docker received is allow-listed; no `rm`, no `cp`, no `run`, no `push`.

Probes (each prints `PASS <name>` / `FAIL <name>: <one-line detail>` / `SKIP <name>: <why>`;
exit 1 on any FAIL; the summary line counts both):

1. `socket_perms` — from `docker inspect` mounts, stat the socket: mode 0600, parent dir 0700
   (contract §3).
2. `oc_port_bound` — inside A, TCP connect 127.0.0.1:4096 must be refused: OpenCode binds
   loopback inside the container and nothing on the host proxies it; reachable here means the
   container was started with an extra publish — FAIL. (The launcher's own port is bound 0.0.0.0
   *on the host* with auth — not probed from inside.)
3. `data_dirs_cross` — inside B, `test -e <A's data dir from A's inspect>` → absent (B's
   namespace has no such path; absence is the isolation).
4. `worktree_cross` — inside A, `broker/bin/request --repo <B> delegate git status --porcelain`
   → exit 125, stderr `broker: unknown repository (unknown_repo)`.
5. `egress_block` — inside A, CONNECT through the container's proxy env for
   `example.invalid` → refused. `lan_side` (a second probe of its own, 12 report lines in total)
   — CONNECT `10.0.0.1:80`, `169.254.169.254:80` (owner Q2 pick: metadata IP included), port 22
   → all refused.
6. `docker_socket` — inside A, `test -e /var/run/docker.sock` → absent.
7. `run_user` — inside A, `test -e /run/user/1000` → absent (default posture; the flag marks
   SKIP-with-warning).
8. `launcher_socket_absent` — inside A, the host launcher socket path (default
   `/run/user/$UID/{project}.sock`, override `--socket`) is not in A's namespace.
9. `token_file` — host side: the token file's mode is 0600; inside A, `env` shows nothing
   matching token shapes (`PROJECT_GH_TOKEN*`, `gho_`, `ghp_`, case-insensitive).
10. `home_ssh` — inside A, `test -e ~/.ssh` → absent (default bind set; flag → SKIP-warning).
11. `hub_prefix_mismatch` (needs `--other B`; hub down → SKIP, FAIL under `--require-hub`):
    cookieless GETs of `/p/B/` and `/p/%2e%2e/` against the hub answer 401/404 — never 2xx/3xx
    into B (read-only rule: no login is performed, so only the unauthenticated shape is
    checkable live; the authenticated pair is step 3's in-process job).

Unit tests (`tools/tests/test_a2_hostile_live.py`): a recording fake `docker` first on PATH with
canned inspect JSON and canned exec exit codes; asserts report shape, exit codes, `--dry-run`
prints the probe plan without any exec, allow-list enforcement (the fake refuses a forbidden
argv and the script turns that into a FAIL line, never a crash), and the not-running refusal
exits 2 before any exec. **The live run itself: NOT VERIFIED** in any worker report — no Docker
in the sandbox (ruling 26 says so out loud).

## Coverage table (threat row → existing test → what A2x adds → step)

| Threat row (source) | Existing test(s) | A2x adds | Step |
| --- | --- | --- | --- |
| A opens B's socket / forges uid (a2 §10) | test_server foreign-peer + socket-mode; a2g test_groups_hostile | refusal-order pin: dir-mode 0700 stops A before peer-cred is consulted | 1 |
| Container spoofs PROJECT_PROJECT / pushes B (a2 §10) | test_config targets-from-config; test_paths with_repo; test_groups_hostile repo-field | live-client end-to-end with spoofed env, fake-git zero-push | 1 |
| Path escape ../, symlink (a2 §10) | test_paths (dots, links, FIFO, recheck) | hard link into B — nlink rule | 1 |
| TOCTOU swap after check (a2 §10) | test_delegate_write spec-file swap; test_push sha-discipline | .git swap for --repo target at push time | 1 |
| git config fsmonitor/hooksPath/etc (a2 §10, contract §6.6) | test_push HARD keys; test_delegate_write (2 of 4) | all 4 via delegate + filter/diff.external non-block + GIT_CONFIG_* env pins via fake | 1 |
| Prompt/command injection (a2 §10) | test_server framing; test_protocol argv rules | bidi/10k end-to-end; ref trailing newline; half-close; 50 concurrent; 1-bad-in-50 | 1 |
| Token exfil (a2 §10) | test_a2a_hostile case 9 (env scrub) | host-side git env pins; token-shaped remote redacted in audit | 1 |
| Reserved name collision broker/hub (a2 §10) | test_config parity; routes RESERVED_HOME_NAMES | case-variant router probes + planted-`Api`-registry belt | 3 |
| Relay forwards to wrong container (a2 §10; a2h X1–X7) | test_a2h_relay X1–X7 | trailing dot, double-encode, reserved set on project row, foreign WS-upgrade | 3 |
| egress: redirect, DNS rebinding, connect-by-IP (a2 §10; a2a 22/23/28) | a2a hostile + A2E egress proxy | plan-level LAN-pin absence; live lan_side probe | 2/4 |
| Resource exhaustion (a2 §10; a2a 33) | test_server cap=8 | 50-connection soak + batch poison | 1 |
| Installer follows planted link (a2 §10; a2a 31) | test_projinstall planted-link ×2 | simultaneous double-plant composition | 2 |
| Migration exports (a2 §10; a2a 32) | oc/tests/test_migrate.py (53 cases) | hostile source-answered fields; payload caps; verify_failed no-delete pin; `existed` idempotency | 2 |
| Broker TOCTOU symlink swap (a2a §11) | a2a case 15 | none new (covered) | — |
| Host Docker socket, /run/user (a2a §11; a2h X19) | a2a 16 + planner mounts | live probes 6/7/8 | 4 |
| Hub prefix mismatch (a2a §11; a2h X17) | a2a 29; test_a2h_relay | step 3 variants + live probe 11 | 3/4 |
| Container-to-container A↔B (a2a §11; a2h X20) | a2a 21; A2F network isolation | live probes 3/4 | 4 |
| Session hijack, anonymity, key/bytes timing (a2 §10) | test_auth + test_a2a_hostile 14/15/18/30 | none new (covered) | — |
| GitHub token / ~/.ssh (task's hostile list) | test_config modes; bind list | env-absence inside A (live), audit non-echo (in-proc) | 1/4 |

## Scope per step (the chain JSON's `scope` mirrors "Files owned")

- Step 1: `broker/tests/test_a2x_write_hostile.py` + fix-scope `broker/paths.py`,
  `broker/server.py`, `broker/protocol.py`, `broker/client.py`, `broker/audit.py`,
  `broker/git_push.py`, `broker/runner.py`, `broker/tests/util.py`,
  `broker/tests/fakes/git` (additive env-record).
- Step 2: `oc/tests/test_a2x_plan_hostile.py`, `oc/tests/test_a2x_migrate_hostile.py` +
  fix-scope `oc/projects.py`, `oc/projinstall.py`, `oc/migrate.py`, `oc/install.sh`,
  `oc/tests/util.py`.
- Step 3: `hub/tests/test_a2x_relay_hostile.py`, `launcher/tests/test_a2x_oc_hostile.py` +
  fix-scope `hub/routes.py`, `hub/projects.py`, `launcher/oc.py`, `hub/tests/httputil.py`,
  `launcher/tests/util.py`.
- Step 4: `tools/a2-hostile-live.py`, `tools/tests/test_a2_hostile_live.py`.

If a needed fix lands outside a step's scope, the step reports it; it does not edit there.

## Owner questions

- **Q1 (pick: adopt).** The nlink rule for *regular files* is stricter than A2-4's wording (it
  names directory links and FIFOs). Hard links are rare in project trees (git doesn't create
  them) but cost nothing to refuse. Adopting closes the gap without breaking any existing test.
- **Q2 (pick: include).** Live `lan_side` probe includes cloud-metadata IP 169.254.169.254.
- **Q3 (pick: SKIP unless --require-hub).** Hub down → hub probe SKIPs (visible, counted), not
  FAIL; `--require-hub` upgrades to FAIL. The suite is about posture, not uptime.
- **Q4 (pick: in step 1).** 50-connection soak stays in-process (threads on the real socket);
  a live `docker exec`-flood probe would be the load generator, which the read-only rule bans.

