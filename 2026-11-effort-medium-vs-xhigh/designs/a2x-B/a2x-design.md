# A2X — hostile acceptance suite, deepened (A2 step 8)

The A2 plan's step 8: *"the hostile suite of §10 end to end, in two layers (ruling 26): the
in-process layer drives the real broker over its socket and the real relay over HTTP, with
fake `docker`/`git`/`gh` executables; a small host script runs the container-layer cases
with `docker exec` as the container's own user. The suite is written to be executable and
deterministic, not prose."* Plus the task's extra list: planner and installer refusals, and
migration hostile bodies.

This slice writes **tests of the components as they stand on `a2-steps-6-8`** — nothing
deployed, nothing live in CI. The one thing that cannot be gated (real `docker exec` into a
running OC container) becomes a checked-in host script plus gate tests for it against a
fake `docker` (§6). No step here pushes, deploys, or runs the live script.

**Chain**: `a2x-chain.json`, base `a2-steps-6-8`, gate `python3 tools/run_tests.py`, two
suites of new modules plus the fixes any found bug requires. Every step `hard: true`: each
one can touch broker/oc/hub/tools runtime code once a hostile case proves a gap, and the
chain's whole point is what a hostile suite finds.

## 0. What this slice is not

A1's daemon, its worktree flows and its ledger are out of scope. The launcher's
`/projects/<name>/...` proxy surface and the admin surface were already hostile-swept by
A2A step 10 (`a2a-10-hostile.md`, running as this slice proceeds) and by
`launcher/tests/test_acceptance.py` — this slice does not re-type them. The groups
boundary got its own hostile suite on this branch (`a2g-4-hostile.md`,
`broker/tests/test_groups_hostile.py`), and the hub's project relay got one in A2H
(`a2h-design.md` §10, X1–X25). This slice covers what those suites do not: the broker
socket's framing and grammar edges against the **current** broker including groups and
service, the planner and installer as attack surface, the relay's project-directory and
identity edges at the gate level, migration hostile bodies, and the container layer as an
executable script. The coverage table (§2) is the contract about who owns which row —
before writing a case, check the row; a duplicated case is wasted reviewer attention, a
missing one is the whole point of the slice.

## 1. The two layers (ruling 26), concretely

**Layer 1 — the gate.** In-process tests, standard library, driven through
`python3 tools/run_tests.py` (handoff §2; module names accepted). Four fixtures, all of
them the real thing:

- **The real broker** over its real Unix socket: `broker/tests/util.py`'s `Fixture`
  already builds a temp home (0700), a real `BrokerServer`, real peer credentials, and
  `call()` which frames bytes the broker's own reader sees. Group-bearing configs come
  from its `groups=` parameter; the service op needs its `docker` path pointed at a fake.
  Fakes here are **paths in broker config**, not PATH (`util.py`'s comment is right:
  putting `broker/tests/fakes` on the PATH would make the system `git` shadow the fake) —
  the broker never resolves `docker`/`git`/`gh` through PATH; its config names them. The
  existing fakes (`broker/tests/fakes/{git,docker,gh,delegate}`) record argv and are
  enough for most cases; a step adds a fake only when it needs new recorded behaviour.
- **The real hub relay** over HTTP: `hub/tests/httputil.py`'s `HubTestCase` (a real
  `ThreadingHTTPServer`, real gate, real session verifier) with `FakeVerifier` for the
  identity and `FakeOpenCode` for the container side, and `write_projects()` for the
  launcher's registry file. Free ports (`bind(("127.0.0.1", 0))`), never fixed ones — the
  runner runs modules side by side (AGENTS.md).
- **The real `oc/projects.py` planner and `oc/install.sh` dispatch**, driven as the
  attack surface they are: `plan_project`/`load_registry`/`binds`/`pin_hosts` called
  directly on temp trees, and `install.sh` executed for real with `HOME`/`XDG_*` into a
  temp root and a recording fake `docker` on `PATH` (the script must find `docker` by
  name, so PATH injection is the honest fake here — unlike the broker, `install.sh`
  resolves it through the shell). This mirrors `oc/tests/test_install.py` and
  `hub/tests/test_h1_acceptance.py`:217–264 (its `docker` shim: a script dir on `PATH`, an
  argv log, `SHIM_LOG` in the env), and the script itself follows the live-check precedent
  that exists in-repo, `hub/tests/livecheck.sh` — including its replay trick, where every
  seam is an override so the gate can replay the transcript against a shim.
- **The fake executables**: on PATH for the installer tests, config-named for broker
  tests. Each records its argv somewhere the test then reads (the `call_log` pattern):
  the assertion for "nothing ran" is "the log is empty", and the assertion for
  "forced and only forced" is the recorded argv, not an exception.

**Layer 2 — the host script.** `tools/a2-hostile-live.py` (§6): run by a human on the hub
host at cutover, drives the **real running stack** with `docker exec` **as the
container's own user** (the container's `USER 1000:1000`, `oc/image/Containerfile:98`) —
exactly the attacker model: whoever holds a shell in one project's container. It never
changes state (§6's rules), prints one `PASS`/`FAIL <id>` line per probe and
`LIVE: <n> probes, <m> failed`, exits non-zero on any FAIL. Its unit tests run in the
gate against a fake `docker` executable (PATH-injected, scripted answers): the PASS path,
the FAIL path (a probe that should refuse but succeeds in the fake → exit non-zero,
`FAIL <id>` printed), and the docker-missing path (exit 2, usage, no traceback, no
container touched). A step that gates green and fails live is a real finding for the
reviewer, which is why the script's output format is machine-checkable from the first line.

## 2. Coverage table — every threat row, who covers it, what this slice adds

Rows are the threat tables of `a2-design.md` §10 and `a2a-design.md` §11 (the two §s the
step text names). "Covered by" cites tests already on this branch; "this slice" names the
A2X case id (§4–§7) that adds to the row — `—` means the existing suite is complete for
that row's in-process half and re-typing it is noise; the row then lives only in the
container layer (L-probes, §6). Check the row before writing a case.

| threat row | covered by | this slice |
|---|---|---|
| A2 §10 cross-project reachability | `a2a-10-hostile.py` mounts; `oc/tests/test_acceptance.py`; `broker/tests/test_mounts.py` | planner matrix K1–K6 (§5); live L-probes |
| A2 §10 container escape | — (not an in-process row) | L-probes only (§6); gate covers the script mechanics |
| A2 §10 token exfil over network | `hub/tests/test_proxy_hardening.py`; `oc/tests/test_proxy_templates.py` | L10–L12 (egress-only, denied hosts, link-local) |
| A2 §10 prompt injection → force-push | `launcher/tests/test_a2a_hostile.py`; `broker/tests/test_push.py` | B24 over the raw socket |
| A2 §10 direct broker socket use | `broker/tests/test_peer.py` | framing/grammar/resource edges B3–B8, B27–B31 (§4) |
| A2 §10 symlink out of project | `broker/tests/test_paths.py` | B20–B22: TOCTOU swap race, hardlink, FIFO — not there |
| A2 §10 git config exec | `broker/tests/test_repocheck.py`; `test_groups_hostile.py` | B16–B19 incl. four `DANGEROUS_KEY` gaps (§4) |
| A2 §10 hub relay `/p/` tricks, reserved names, identity headers | `hub/tests/test_relay.py`, `test_projects.py`, `test_proxy_hardening.py` | R1–R9 gate-level byte-exact refusals (§5) |
| A2 §10 migration hostile request bodies | `oc/tests/test_migrate.py` (well-formed only) | M1–M6 (§7) |
| A2A §11 launcher command-construction edge | `launcher/tests/test_oc.py`; `test_a2a_hostile.py` | K4 name grammar; K5 spec mismatch (planner side) |
| A2A §11's mirror rows (escape, exfil, force-push, socket, symlink, config, relay) | the same suites as above | the same A2X ids — one row set serves both tables |

`a2a-10-hostile` (step 6, launcher side) owns: hidden-hop, token replay, admin CSRF,
launcher path traversal, raw-socket method/path shapes, the launcher's reserved names,
`--user`/`--label`/`--mount`/`--env` force checks, no-555-socks, no-token-on-argv. Those
are **launcher** surfaces; A2X re-derives none of them except where the same hostile shape
meets the broker socket (B), the planner (K) or the hub gate (R) — which is this slice's
contribution.

## 3. The rules the tests obey

- **Tests are the spec.** A hostile case that fails is a bug **in the component** — fix
  the component, in the step that surfaced it; the fix's files are named in that step's
  "Files owned" under *fix targets*. Never loosen a test, never xfail, never skip
  (handoff §5). A case that cannot pass without a change beyond the step's scope blocks
  the step and is escalated in its report, not adjusted.
- **Every refusal asserts three things**: the exact error shape (§4's shape table); no
  side effects (the fakes' recorded argv empty or exactly the allowed calls; marker files
  absent; the promised audit line present); and the answer carries no more than the
  contract's sentence — no real path, secret, token or container name in a broker answer,
  no identity material in a hub body.
- **Isolation.** New modules set `HOME`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`,
  `XDG_DATA_HOME`, `XDG_CACHE_HOME` and the `PROJECT_OC_*` paths into their temp root
  themselves (ruling 24c; the host exports `XDG_CONFIG_HOME` and runs umask 002 — a 0775
  dir the host created first fails a mode-0700 assertion, handoff §9). `run_tests.py`
  fingerprints the owner's real `~/.{project}`/`~/.config` as a backstop. Ports bind to 0
  (`bind(("127.0.0.1", 0))`).
- **No site values** (`hub/tests/test_anonymity.py` enforces it for the hub): sample
  projects `web-app`, `api-svc`, `other-proj`; homes under `tempfile.mkdtemp()` only.
- **Determinism.** A TOCTOU case uses a fake executable that *observes* the swap, not a
  thread timer (B20). Broker timings stay at defaults (handoff §9). Same expectations on
  python 3.12 (sandbox) and 3.13 (host) — no version-conditional assertions.
- **Worker runs** (delegate-rules §7a): `python3 tools/run_tests.py <step modules>` while
  working; the step's verify runs the **full** gate once (every A2X step is hard).

## 4. Layer 1a — the broker socket (`broker/tests/test_a2x_hostile.py`)

Drives the real broker over the socket with `broker/tests/util.py`'s `Fixture` (real
peercred, `Peer` for raw bytes). Shapes, cited from the code as it stands:

- **Socket refusal**: one JSON line `{"ok": false, "error": <code>, "detail":
  DETAIL[code]}`, `arg` only for a code that rides its argument (`broker/protocol.py:422`
  `answer_error`; `protocol.DETAIL` at :17). An unlisted code collapses to `failed`
  (:433) — a test that asserts a named code *is* the regression fence against collapsing.
- **Hub gate bodies**: `hub/gate.py:49–60` (`BODY_403 = _body({"error": "forbidden"})`
  and siblings); byte-exact assertions compare the gate's own constants.

| id | case | expected (cited) |
|---|---|---|
| B1 | `Peer` with a second, foreign uid | closed with **no bytes** (`test_peer.py:64` asserts exactly this); audit gains `peer_refused peer=uid<N>` (server.py:137) |
| B2 | project dir removed after config load, request still arriving | `outside_project` + its DETAIL (server.py:397–405; paths.py:122) |
| B3 | 256 KiB line, over `MAX_LINE` | `too_large` + "the request line is too long." then close (protocol.py:24; server.py:581–583 — the early refuse only once the line cannot become legal) |
| B4 | 10 000- and 70-element `argv` | `invalid_request`; order is framing → shape → op → keys → values ("check in that order and answer the first failure", contract §4) |
| B5 | one non-string element among strings; a 100 KB value | `invalid_request`, then `toolarge_value` at 64 KB (`MAX_STRING`) |
| B6 | op `"delegate "`, `"Delegate"`, `"nope"` | `invalid_request` "no such op: …" — DETAIL's sentence lists the four ops and no fifth |
| B7 | bytes after the newline | `bad_request` + close (server.py `_read_line`) |
| B8 | slow trickle then close; slow-loris 6 s | silent close, no answer, no demand line (server.py:567–577); a later good request from the real peer answers `ok` |
| B9 | `cwd` `""`, `".."`, `"a/b"`, `"/etc"`, absent | `outside_project` for the escapes (paths.py:189); `no_repo` for absent only when no single collab member exists (contract §6, repocheck.py:428–433) |
| B10 | `repo` = `""`, `"."`, `".."`, `"a/b"`, `"~"`, `"$HOME"`, `".hidden"`, unknown, another project's member, a read-only member, a plain dir | `unsafe_git_arg` for `"" . .. a/b`; `outside_project` for `~`/`$HOME`/`.hidden` (paths.py:161–172); `unknown_repo` for unknown/foreign/plain-dir (resolve_member's three collapse, repocheck.py:329–363 — byte-equal answers, assert equality so the set cannot leak); `not_a_target` for read-only |
| B11 | groups config: `--repo` a *foreign* member; a dot-named member; `..` inside a member bind | `unknown_repo` byte-equal to B10's truly-unknown answer; bind escape still `outside_project` (a2g-4's H22 covers the child env; this is the socket-side pair) |
| B12 | `other-proj`'s task id in `top`; on shared repo, foreign id with a valid task | `unknown_task` (tasks.owned); `shared_repo` only when the id is real and foreign (repocheck.py:382–388) — construct both, pin both |
| B13 | `service` argv over `MAX_ARGV`; `create postgres --name ../x` | `invalid_request`; `bad_service_name` before any spawn (services.py:234 — `bad_service_name` sits in `SERVICE_PRE_SPAWN_CODES`); fake-docker log empty |
| B14 | `gh pr create` with no `github.repo` in config | `gh_refused` before spawn (gh.py; contract §7); fake-gh log empty |
| B15 | `push --force` without `--yes`; a non-noreply stack | `force_default` (fake-git log empty — refused before spawn, contract §7.2); `not_noreply` **with** its `commits`+`count` extras (protocol.py:429–436) |
| B16 | repo sets `core.fsmonitor=/tmp/marker`, `core.hooksPath` into the project; run `delegate top` | `unsafe_config`, marker never touched (repocheck.py:48–49); fake-git's recorded env has `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1` |
| B17 | repo sets `credential.helper`, `diff.external`, `remote.origin.pushurl`, `url.<x>.insteadOf` | **known gap**: `repocheck.DANGEROUS_KEY` (repocheck.py:38–54) lacks all four on the delegate path (push's `FORCED_CONFIG` strips them, git_push.py:52–60). Step 2 extends the shared table; the test asserts `unsafe_config` on **both** paths and that a clean repo still passes push (the fix must not break it) |
| B18 | dangerous key written across a line continuation / unicode escape | `unsafe_config` — if the scan misses it, fix the scan, don't soften the case |
| B19 | fsmonitor-capable repo reached only through target resolution | fake-git argv: no `config` call before the allow-list check returns (order as of repocheck.py:330–363); on refusal the only recorded call is the `config --show-origin` read |
| B20 | swap race, deterministic: fake `delegate` swaps `task/…/link → ../outside` (from `→ inside file`) before exec | `outside_project` — the after-open recheck sentence (paths.py:199–204 "swapped under us"); outside marker's content in no frame, child argv (fake log) carries no swapped content |
| B21 | hardlink into project, then its twin points outside and is renamed onto the `task/` slot in the check→use window | `outside_project` (the `S_ISREG`+`O_NOFOLLOW`+recheck stack, paths.py:143–204); never `ELOOP` leaked as text |
| B22 | FIFO as the `task/` file | `outside_project` before resolution (S_ISREG first), **no hang**: wall time < 2 s, connection closed cleanly |
| B23 | `--copy` × 51 as a `run` argv, and ×51 as a plan's `copy` list | the first is `bad_request` from `_argv` (`MAX_ARGV` = 64 elements, `protocol.py:23` and `:330`) with the fake's log empty; the second **passes today** — `_copy_ok` (`plans.py:195–202`) checks each name's shape and no count — so the assertion is how many files land in the spool, that each is a plain 0600 file, and that a refused request leaves none (§11). That asymmetry is the slice's finding rather than a failed test: the argv is capped and the list is not |
| B24 | one 300 KB copy among three good ones | `copy_too_large`, spool `requests/` empty after (the §11 delete-on-refusal; contract §11), the 300 KB nowhere in the answer; 128 KB passes |
| B25 | `delegate push --yes --force`; `push` op with `--force-with-lease` | `refused_flag` for the first (before the verb's grammar, contract §5's order); `unknown_arg`-shaped `invalid_request`… for the second assert the actual code (`unknown_arg`) — pin whichever the grammar gives, both refuse with empty spawn logs |
| B26 | half-open connect/close; write-close-write | silent closes, no traceback (broker stderr stays clean), later good request answers `ok` |
| B27 | a `\u0000` inside a value at depth 3; a line that is not valid UTF-8 at all | `bad_request` both times (`_strings` :397–408 for the NUL, `parse_line`'s decode/parse failure for the bytes), with **no** `arg` and no echo — assert the request's literal text appears nowhere in the answer; a fresh `Peer` afterwards works normally (one request per connection, contract §4) |
| B28 | 50 connections, 5 malformed | own verdict per connection; ≤ `max_running` concurrent children in the fake log (handoff §9 default 2); `busy` refuse carries `running=`; every audit line parses alone (append-only line atomicity) |
| B29 | a 200 KB *key*; an unknown key `argvv`; one line carrying `argv` twice; a nested object where a string belongs | all four `bad_request`: `_strings` recurses into keys (:400), `_keys_of` refuses the unknown (:310–326), `_no_dupes` refuses the duplicate instead of letting JSON's last-wins quietly drop a flag (:374) — that last is the shape a hostile line can really use, so the test pins the refusal and not a fallback |
| B30 | same-uid foreign process (documented trust boundary) | **accepted** — kernel peercred is forgeable only off-host; the container half is L10. The test exists to keep the boundary stated, not silent |
| B31 | 2 collab members, neither `cwd` nor `--repo` | `no_repo`; DETAIL names nothing (protocol.py:59–61), audit line has no `member=` field (contract §8, PRE_TARGET_CODES server.py:610) |

Every B-case also asserts the audit line the contract promises (`refuse(..., member=…)`),
and its **absence** when the target never settled (`PRE_TARGET_CODES`, server.py:610).

## 5. Layer 1b — the planner and the hub relay

### 5a. Planner + installer (`oc/tests/test_a2x_planner.py`)

The real `oc/projects.py` (`plan_project`, `load_registry`, `binds`, `pin_hosts`,
`create_argv`, `network_argv`) on temp trees, plus `oc/install.sh` executed for real (fake
`docker` on PATH, temp `HOME`/`XDG_*`). `CONTAINER_PREFIX = "{project}-oc-"`,
`EGRESS_NAME = "{project}-oc-egress"` (projects.py:39,41).

| id | case | expected (cited) |
|---|---|---|
| K1 | two projects sharing one bind source; overlapping dest names | the real rule, pinned: binds() keys by dest (projects.py:177–187); neither plan's mounts contain the other's `.{project}-home`/`.oc-config` (per-project dirs, projects.py:590–591) |
| K2 | A's `.oc-config` path written into B's registry as a bind host | `PlanError` key `mount` "… is not inside …" (projects.py:683–688) |
| K3 | `home` = another project's dir; home containing `..`; home under a symlink | `home`/`mount` refusals at projects.py:155–161, 659–663, 696–702 ("is a link or not a directory") |
| K4 | name `web-app;rm -rf /`, `web app`, `--privileged`, 200 chars | key `name` "not one docker can take" via `NAME_RE` (projects.py:37, 219–222); nothing reaches a fake-docker argv |
| K5 | stored `spec` ≠ recomputed; `spec` deleted; foreign `written_by` | `registry` refusals — spec is compared, never recomputed live (projects.py:876; contract §3); fake-docker log empty |
| K6 | registry mode 0644; symlink at the path; foreign owner where testable | "is not mode 600" / "is a link" / "is not owned by this user" (projects.py:818–826) |
| K7 | `extra_hosts` pin → `127.0.0.1`, `169.254.1.1`, `metadata.google.internal` | `pin_hosts` refuses loopback today (a2i-1); non-global addresses: step 3 extends the refusal to anything outside public-unicast (the DNS-rebinding face of the exfil row); pin both before/after in one test file |
| K8 | egress allow-list `*.example.com` + literal IP; `egress.enabled` false | planner emits wildcards verbatim (squid matches them, contract §3.4); disabled egress: no egress container in `network_argv`, no `HTTP_PROXY` in `create_argv` (projects.py:264–267) — `--internal` still isolates |
| K9 | `install.sh migrate` with `PROJECT_OC_PROJECT` unset / unknown; `projects stop` twice | exit 2 + `ERROR invalid_request …` (projinstall.py:42–44) / "no such project" / idempotent stop (fake-docker argv shows no start on the second) |
| K9 | `python3 -m oc.projinstall` invoked **directly** without the env `install.sh` injects; `--project unknown-name`; `projects stop` twice | the pin guard refuses first: `refuse("the OpenCode pin is not in the environment; run this through …")` (projinstall.py:252–254) → Usage → exit 2 (projinstall.py:1130); an unknown `--project` name is a usage error by its own docstring (projinstall.py:407); stop is idempotent — the second stop's fake-docker argv shows no `start`/`run` |
| K10 | `install.sh` executed with a **relative** `HOME`; pre-existing symlink at the registry path (`registry_path_of(env)`, projects.py:121) asserted via the dispatch (install.sh:66–72 execs `python3 -P -m oc.projinstall`); registry dir pre-created 0775 by a hostile umask | assert the real behaviour first, then fix in step 3: the symlinked registry must refuse through `load_registry`'s "is a link" (projects.py:820) as a nonzero `install-failed`-class exit with no docker call (fake log empty), and the dir mode lands 0700 whatever the caller's umask (projinstall's own `makedirs(mode=0o700)` at :693 and `make_real_dir(…, 0o700)` at :703 — the umask-002 trap, handoff §9) |

### 5b. Hub relay gate (`hub/tests/test_a2x_relay.py`)

The real gate over HTTP via `hub/tests/httputil.py`'s `HubTestCase` (real
`ThreadingHTTPServer`, real gate ordering, `FakeVerifier` for the identity,
`FakeOpenCode` as the container). The fixed bodies are `hub/gate.py:49–60`
(`BODY_400/401/403/404/405/411/413/415/421/501/503/505`, each `_body({"error": …})`);
byte-exact assertions compare the module's own constants, never a re-typed dict. The
project rows are the P-rows of `hub/routes.py:408–430`; the response drop list is
`proxy.PROJECT_DROP` (proxy.py:102); the upgrade test is `wsrelay.is_websocket_upgrade`
(wsrelay.py:64–75). X1–X25 stay in `hub/tests/test_relay.py`; these are the byte-exact
shape and identity rows that suite does not pin:

| id | case | expected (cited) |
|---|---|---|
| R1 | unauthenticated `/p/web-app/`; with `Cookie: sid=stolen`; with `X-Project-*` identity headers forged on the wire | `401` + `BODY_401` byte-exact (gate.py:50), no `Set-Cookie`; every forged identity/session header dropped from the proxied request (assert on `FakeOpenCode`'s received headers — neither forged name present); nothing proxied for the unauthenticated half |
| R2 | `/p/web.app/`, `/p/web%2Fapp/`, `/p/web-app/./a`, `/p/web-app/../admin`, `/p/web-app/%2e%2e/admin`, `//p/web-app/` | each refused at the route table — `404` + `BODY_404` (or `400` for an undecodable target: pin which `classify` gives, routes.py:247) — **never** `503` (which would confirm *known project, offline*), `FakeOpenCode` receives nothing, and the `../admin` literal never reaches the P-rows |
| R3 | `/p/p`, `/p/api`, `/p/assets`, `/p/auth`, `/p/settings`, `/p/session` (the reserved set, `hub/routes.py:79–80` == `broker/config.py:55`) | each byte-equal to an unknown-project `404`, so reservation leaks nothing (routes.py:316–319 refuses a *config* that names a reserved project — that half is K4's; this is the wire half); `404` byte-equal whether the name is reserved-and-live-shaped or never-known |
| R4 | `GET /p/web-app/api/pty` with no id; `PTY_ID_RE`-breaking ids (`../x`, 65 chars, empty); `Connection: upgrade` on a plain `/p/web-app/` | `404`/`400` per the route table (`PTY_ID_RE`, routes.py:193); a `Connection: upgrade` on a non-allow-listed row stays an ordinary P-route answer, never a `101` (wsrelay.py:64–75) |
| R5 | `POST /p/web-app/session/x/message` with `Content-Length: 314572800`, no `Content-Length`, `Transfer-Encoding: chunked` | `413`/`411`/`501` byte-exact (gate order: framing before identity before route), and `FakeOpenCode` sees **nothing** — the body is never read off the wire |
| R6 | `/p/web-app/api/fs/read?path=/etc/passwd`, `…?path=../../etc/passwd`, a `file=` query on a non-fs P-row | the broker's refusals are the model (`not_a_file` for a symlink/FIFO/dir, `outside_project` for escapes, paths.py:176–204); the relay's half is byte-exact at this gate, and no container-side bytes echo the escaped path back (the relabel exception applies only to the exact `/api/fs/read` shape — proxy.py's drop discipline) |
| R7 | `OPTIONS`/`TRACE`/`DELETE` on a P-row that takes none; `PATCH /p/web-app/session/x` where the table allows it | `405` + `BODY_405` with an `Allow` header; `501` for TRACE per the gate; the allowed PATCH is proxied — asserted by `FakeOpenCode`'s received-requests log, the only side-effect oracle here |
| R8 | container answers `Set-Cookie: sid=x`, `WWW-Authenticate`, `Location: http://evil/`, `Refresh`, its own `Cache-Control` and CSP | the client sees `relay_response_headers`'s list (:387–420) exactly: `RESPONSE_DROP` (:78) takes hop-by-hop + `Set-Cookie` + `WWW-Authenticate`; the project kind's `is_project_dropped` (:219–222, `PROJECT_DROP` :102–107) takes `Location`, `Refresh`, the report-only CSP, `X-Frame-Options`, every `access-control-*`; `Cache-Control` is replaced; `PROJECT_ADD` (:111–116) appended — no `evil` byte anywhere (a2h §6.2) |
| R9 | two projects live; principal B's cookie on project A's URL; a Host header that is a second hostname of the same origin | `421` + `BODY_421` for the misdirected host (gate: host before identity), `403`/`404` for the cross-project session per `classify`'s answer — pin which, byte-exact, nothing proxied either way |

## 6. Layer 2 — the host script (`tools/a2-hostile-live.py`) and its probes

Stdlib-only Python; structured like `hub/tests/livecheck.sh` (preflight → numbered probes
→ one summary line → exit), with its replay trick: every external seam (`docker` binary
path, registry file, the two project names) is a flag or an env override, so
`tools/tests/test_a2_hostile_live.py` can run the whole probe list against a shim.
**Never changes state**: read-only probes only — no writes at all except inside the
container's own `/tmp`, where a probe writes it removes in the same
command; no `stop`/`rm`/`pull`/`create`; no broker verb that creates a task (the delegate
half is `doctor` and `list` only); no host writes; `SKIP <id> <why>` counts as pass and
prints why. Output: one line per probe, `PASS <id>` / `FAIL <id> <one-line why>` /
`SKIP <id> <why>`, then `LIVE: <n> probes, <m> failed`; exit 0 when `failed=0` (skips
included), non-zero on any FAIL, exit 2 for a refused invocation (usage line, no
traceback). Execs run as the container's own user — `docker exec --user 1000:1000
<CONTAINER_PREFIX><project> sh -c '…'` (oc/Dockerfile:116 `USER 1000:1000`), never root.
Refuses (exit 2, before any docker call) without `--project A --other B`, when either name
is absent from the registry file it is given, or when `docker` is not on PATH.
`--dry-run` prints the docker commands and exits 0.

| id | probe (as the container user) | pass = |
|---|---|---|
| L1 | `id -u`, `id -g` | both 1000 — the attacker model holds |
| L2 | `ls /proc/1/root`, `cat /proc/1/environ` | EACCES/EPERM, or pid 1 is the container's own entrypoint and its environ unreadable to us — never host init |
| L3 | `test -e /run/{project}/broker.sock`; `stat -c %a` of it and of `/run/{project}`; `test -w` both | the socket reachable **but not writable** (handoff §7 item 9: the fix is the bind's mode, not its presence); the dir not writable |
| L4 | `test -d /srv/{project}/oc/projects/<other>`; `test -e $HOME/.{project}`; `ls /root` | other's tree ENOENT/EACCES (binds carries only this project's member trees, projects.py:221–227); no {project} state root mounted (the `projects.<P>` refusal is the builder's proof, this is the runtime one); `/root` refused |
| L5 | `env`, `tr '\0' ' ' < /proc/1/cmdline` | no `*TOKEN*`, no `*KEY*`, no `OC_PASSWORD` value — the password travels as the 600 file the entrypoint reads (projects.py docstring :7–9), so nothing secret is in the environment at all |
| L6 | `cat ~/.gitconfig`; `ls ~/.config/gh ~/.ssh`; `cat ~/{claude-dir}/settings.json` | the copy matrix as the user sees it: settings copies present if the image says so, credentials absent (`test -e` fails) |
| L7 | `touch /etc/passwd /usr/local/bin/x /run/x`; `mount | grep ' / '` | every one EACCES/EROFS; `/` shows `ro` (the `--read-only` flag, projects.py docstring :12–13) |
| L8 | a stdlib `AF_UNIX` connect to the broker socket, then one `doctor` line | **the live twin of B1**: connect may succeed (L3), the answer is EACCES, or a closed connection with **no bytes** — a broker refusal with the peer's uid in its face would be a leak and would FAIL; on the host side, `peer_refused` appears in the broker's audit (server.py:149) |
| L9 | `{project}-broker doctor` (oc/bin) plain; then with `--repo` forged into the op's argv | plain answers a valid verdict line or the documented unreachable message (client.py:194); the wrong-op `--repo` shape answers `bad_request` (validate's key check, protocol.py:300–303) — the CLI mirror of the §4 table, contract §11's CLI shapes |
| L10 | `env | grep -i proxy`; a connect to an allow-listed host the site config names (SKIP if none) | `HTTP(S)_PROXY` point at `{project}-oc-egress:3128` (projects.py:282, 291–294); the allow-listed host answers — egress path works before we prove it is the *only* path |
| L11 | `getent hosts <self-container>`; `<other-container>`; a connect to other:4096 | self resolvable, other unresolvable or refused: cross-project reach denied from inside (L4's wire twin) |
| L12 | `urlopen` (stdlib) to `http://169.254.169.254/`, to the host gateway ip on the launcher/hub ports, and `https://github.com` direct with the proxy env cleared | all three fail within 5 s: link-local, host-side, and off-egress direct (the `--internal` network is the wall) |
| L13 | inside `{project}-oc-egress` only with `--egress`: `test -r /var/lib/squid/ca.key`; `id -u` | EACCES and uid of the `squid` user — a2h §4's claim live (a2i-4's unit twin) |
| L14 | `cat /etc/hosts` | the configured pins present verbatim; no loopback/link-local/metadata pin exists (K7's runtime twin) |

(L15+ deliberately unassigned: ids A2H's live script and A2A-10's live half already own —
proxy-bypass and CA distribution — so readers of both scripts see disjoint sets.)

**Unit tests** (`tools/tests/test_a2_hostile_live.py`, in the gate): a fake `docker`
executable on PATH replaying canned stdout/stderr per probe from a fixture file. Assert:
(a) all-PASS fake → exit 0, one line per enabled probe, `LIVE: <n> probes, 0 failed`;
(b) a fake where one read that must be EACCES returns content → that exact `FAIL <id>`
line, exit non-zero, the summary counts it; (c) `docker` missing from PATH → exit 2,
usage line, no traceback, fake's call-log empty (the script never guessed — it runs only
through the docker seam); (d) `--dry-run` → commands printed, no exec in the call-log;
(e) missing/unknown `--project`/`--other` → exit 2 before any docker call (call-log
empty); (f) every exec's argv carries `--user 1000:1000` and the container name is exactly
`CONTAINER_PREFIX + name`, recorded as separate argv elements (the fake dumps `printf
'%s\n' "$@"`) — no project name interpolated into a shell string.

## 7. Migration hostile bodies (`oc/tests/test_a2x_migrate.py`)

The hostile half of `oc/migrate.py` (M1–M3, M5–M6) plus the `oc/sessions.py` import that
backs it (M4). `oc/tests/test_migrate.py` covers well-formed fixtures; the reason
vocabulary is `migrate.REASONS` (migrate.py:51–53: `no_project`, `parent_missing`,
`not_selected`, `directory_missing`, `no_container`, `too_large`, `export_failed`,
`import_failed`, `parent_not_carried`, `verify_failed`); the CLI error shapes are `Usage`
→ exit 2 and `Failure(code)` → that code (migrate.py:68–76, 795–808). The launcher/hub has
**no migrate route** (none in `hub/routes.py`) — the migration surface is the CLI over a
socket, so there is no route-side case.

| id | case | expected (cited) |
|---|---|---|
| M1 | the two caps, forced small rather than filled big: `MAX_SOURCE_BYTES` (100 KiB, :40) met by a fake `oc/sessions.py` of `cap`+1 bytes in a fake checkout; `MAX_PAYLOAD_BYTES` (64 MiB, :43) met by a fake `run` seam whose export answers `cap`+1 bytes *after the constant is patched down*; garbage JSON; 400-level bracket nesting; a valid-but-deep tree | the first is `fail()` → `Failure`'s exit with the message that names both numbers (:105–108); the second is the report reason `too_large` (:583–584), the third and fourth `export_failed` via `_export_doc`'s `None` (:631–644) with **no traceback** — stdout is clean; the run continues with the next session; the fake's log shows no `start`/`stop` for the refused file's container |
| M2 | `--report` whose parent is a symlink; a 0775 pre-created parent; an existing file at the path; the default path's parent (`default_report_path`, migrate.py:650) | report written mode **0600** (migrate.py:13) — asserted by stat; a hostile parent refuses rather than being opened world-wide; an existing file is replaced or refused per the code's real choice, pinned with its citation; the report names ids and directories only (migrate.py:15) — assert no secret-shaped string ever lands in it |
| M3 | hostile bytes *inside* session data: `cwd` fields of `/`, `~`, the other project's tree; session ids with `\x00`/newline/`..`; unicode look-alikes | they stay data: reported (ids/dirs only), nothing planned or created from a `cwd` field (the planner is the gate — K3/K4's refusals make a poisoned field inert); the registry does not grow; no fake-docker `create`/`run` names an attacker path |
| M4 | the import's temp file, `sessions.py:339–348`: pre-create a *predictable* `/tmp/{project}-session-import.json` as a symlink to `$HOME/landmine`, then run the import normally; and the same with the mkstemp name guessed at nothing (the attacker pre-creates an `O_EXCL` slot: `mkstemp` fails with `EEXIST`-class `FileExistsError` and the import must not fall back) | **pin, no fix expected**: `mkstemp` + `fchmod(0o600)` + `fdopen` is already the shape (:339–341), and the assertions are that `landmine` is byte-identical, that the temp file's recorded mode is 0600 at the moment the CLI reads it (the fake `oc` helper stats it), and that the `finally`'s `os.unlink` (:348) leaves nothing; a world-readable import temp file, or a follow, is the failure the case exists to catch — then the fix is in `oc/sessions.py` and the test stays |
| M5 | two concurrent `oc.migrate` runs over one registry and one shared container, both woken by the `started_by_us` discipline (:206, :293–302) | first the *pin*: the exports themselves are read-only `exec`s, so both reports are written and no session is carried twice — the counters sum, the two report files are distinct paths (the timestamped default, :650–654) and both 0600. The *finding* the case looks for is the lifecycle fight: run A's finally-stop landing while run B is mid-import. If the run shows it, the fix is a CLI-level claim — an `O_CREAT\|O_EXCL` lock file in the data root, 0600, removed in the same finally, refused with `Failure`'s own exit path (:68–76) — deliberately **not** a new `REASONS` entry: the report's vocabulary is a contract (`a2i-5-migrate.md`) and "another run holds the container" is a usage error, not a per-session reason |
| M6 | `--from`/registry pointing at a nonexistent project dir; a **symlinked registry** file (migrate.py:119 `--registry` is a PATH_FLAGS entry, so it reads through the same loader, projects.py:820 "is a link"); a report path *inside* a project mount | `no_project`/`directory_missing` per REASONS; the symlinked registry is a `Failure` nonzero with no container call (fake log empty); a report inside a mount is allowed but must appear in no fake-docker argv (the container never reads it) |

## 8. The steps

1. **`a2x-1-broker-wire.md`** — B1–B15 plus B23/B27/B29: the socket's framing, grammar,
   cross-project and resource edges against the current broker. New
   `broker/tests/test_a2x_hostile.py`; a new mode on an existing fake only where needed. Expected to gate green on first run:
   these pin today's cited behaviour.
2. **`a2x-2-broker-files-config.md`** — B16–B22, B24–B26, B28, B31: git-config exec (incl.
   B17's four-key table gap), the TOCTOU/hardlink/FIFO trio, copies, concurrency. Fix targets
   `broker/repocheck.py` (the `DANGEROUS_KEY` table), `broker/delegate_rules.py` (the
   shared forbidden-key use), `broker/paths.py` only where a case proves a gap.
3. **`a2x-3-planner-relay.md`** — K1–K10 and R1–R9. Fix targets `oc/projects.py`,
   `oc/install.sh`, `oc/projinstall.py` (K7/K10's refusals), `hub/gate.py`/`hub/proxy.py`/
   `hub/routes.py` only where a byte-exact assertion pins a real gap.
4. **`a2x-4-migrate-live.md`** — M1–M6, and the live script with its unit tests:
   writes `tools/a2-hostile-live.py` (the units require it; probes implemented against
   the fake) plus `tools/tests/test_a2_hostile_live.py`. Fix targets `oc/migrate.py`,
   `oc/sessions.py`.
5. **`a2x-5-coverage-closeout.md`** — the closeout: re-fill the coverage table's "covered
   by" cells against the suites as they actually run on the squash, add any probe-id gap
   the first four steps exposed (script + units), add the slice's own hostile probe script
   `review/a2x-hostile.py` (handoff §6's pattern: independent checks, PASS/FAIL totals), run
   both full suites, and record the findings: one row for the new script in handoff §6's
   table, and one numbered line per open finding in handoff §9 (Loose ends). No
   `tools/check_specs.py` exists on this branch — the checks are the two full suites and the
   scripts in `review/`. Last step of the chain; hard.

The chain is `docs/specs/a2x-chain.json`: `name` `a2x`, `repo` `../..`, `base`
`a2-steps-6-8`, `gate` `python3 tools/run_tests.py`, `retries` 2, five steps, every one
`"hard": true` (each writes a hostile boundary, and the last is the chain's end). Each
step's `scope` list is that step's "Files owned", nothing more; each `verify` runs the whole
gate into `${DELEGATE_EVIDENCE_DIR:-/tmp}/verify-a2xN.log`, greps the step's own `^ok`
lines and its neighbours', fails on any `^FAIL`/`not ok`, and then applies the step's one
static fence (the case-count, the fix's grep, the script's `--dry-run` flag).
Each step is one worker-session sized block (roughly 60–90 minutes); no module is owned by
two steps. Verifies (in the chain file): the step's modules with the gate's `^ok <module>`
grep, the scope guard against the previous step's branch, and — every step here being
`hard` — one full `python3 tools/run_tests.py` pass at the end.

## 9. Owner questions

- **Q-X1 (B17's fix shape).** `credential.helper`, `diff.external`,
  `remote.origin.pushurl`, `url.<x>.insteadOf` are executable-adjacent on the delegate
  path (`git status` can invoke them) and merely stripped by `FORCED_CONFIG` on the push
  path. Assumed: extend `repocheck.DANGEROUS_KEY` (repocheck.py:32–35) to all four on both
  paths — refuse on delegate, push keeps its clean-repo behaviour (B17 asserts both). If
  they should instead stay push-stripped-and-delegate-passing, step 2 becomes a
  pin-the-gap test — say so.
- **Q-X2 (probe set vs the 2–5 step limit).** 14 live probes in **one** script with gate
  units, per A2H's pattern (handoff §4: a live script is host-run, its unit tests gate).
  Alternative: split read-probes from egress-probes into two scripts as A2H did — not
  assumed: one cutover invocation is the safer ritual.
- **Q-X3 (B30, same-uid peers).** Pinned as *accepted behaviour with the boundary stated*,
  not as a refusal: kernel peercred is forgeable only off-host, and the container attacker
  cannot mint the broker owner's uid (L8 proves the container half live). A second OS user
  per project is a component, not a test — flag it for A3 if wanted.
