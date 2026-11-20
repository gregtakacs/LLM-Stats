# a2x-4 — The live cutover script and the owner's runbook

**Goal.** Ship the layer no sandbox can run: `tools/a2-hostile-live.py`, the read-only probe
script the owner runs once per project pair at cutover to prove what A's container *actually*
holds and can *actually* reach — plus the runbook that schedules it, and the unit tests that make
the script trustworthy without a Docker daemon. Design `docs/specs/a2x-design.md` §6 (probes
P1–P9, the never-change-state rule) and §7. **The worker cannot run the live probes: no Docker
in the sandbox (ruling 25).** The worker's job is the script, the unit tests against a fake
`docker` on PATH, and the runbook; it says plainly in its report that the live run is the
owner's.

**Read first.** `docs/handoff.md`; `docs/specs/a2x-design.md` §2 (why two layers), §6, §7, §8;
the script's style and replay-test precedents: `hub/tests/livecheck.sh` (PASS/FAIL line format,
`SUMMARY pass=N fail=N`), `hub/tests/test_h1_acceptance.py` (replays the script against shims —
the technique your unit tests copy); the probe subjects: `oc/projects.py` (what the plan promises:
sock dir `/run/{project}/sock`, no publish, internal net, egress at `EGRESS_NAME:3128`),
`oc/entrypoint.sh` + `oc/Dockerfile` (what's in the container: python3, the broker, the client),
`docs/specs/a2-design.md` §5. **Fix scope: none** — this step creates the script; bugs are its
own fix, not anyone else's file.

**Files owned.** `tools/a2-hostile-live.py`, `tools/tests/test_a2_hostile_live.py`,
`docs/a2x-cutover.md`.

## Contract (the script, precisely)

| Item | Rule |
|---|---|
| Invocation | `python3 tools/a2-hostile-live.py --project A --other B [--registry PATH] [--via-docker [PREFIX…]] [--dry-run]`; in the stdin-injection form (`docker exec -u <uid> {project}-oc-A python3 - … < script`) no docker at all is touched — `--via-docker` wraps each probe in `docker exec` for host-side one-command use (owner question 1/2's picks) |
| Args | missing `--project`/`--other`, or either name not in the visible registry → **exit 2**, no probes run, `FAIL args <reason>` line; the registry defaults to `/run/{project}/projects.json`, `--registry` overrides |
| Output | one line per probe: `PASS <id> <one-line proof>` / `FAIL <id> <observed>`; final `SUMMARY pass=N fail=N`; exit 0 iff all PASS and no probe skipped-as-error; unknown probe → FAIL, never a crash or traceback (every probe wrapped) |
| State | **read/connect/refused-request only.** No writes outside the container's own `/tmp` scratch (its pid-named dir, removed at exit); never create/remove/restart any container, network, volume; never send a push/`up`/`import`/`compose`; the only requests it sends are ones that must be refused or authenticated-401. A probe that would need a state change is not in the script — it is manual in the runbook, marked `SKIP` by the script with its own line |
| Stdlib only | `argparse`, `json`, `os`, `socket`, `stat`, `subprocess`, `tempfile`, `time`, `urllib.request` — nothing else |

## Probes (design §6's table is the normative list; each prints its own proof line)

- **P1** loopback OpenCode port answers 401 unauthenticated inside the netns (a real
  `urllib`/socket request); through `--via-docker`, nothing listens on the host side for A's
  port (the `docker port` output for A must be empty).
- **P2** B's socket: `os.stat("/run/{project}/sock/<B>/broker.sock")` → EACCES/ENOENT, and
  `socket.connect` → refused/EPERM; both outcomes print which they were.
- **P3** A's socket exists, mode **0600**, and `python3 /opt/{project}/broker-client.py … list`
  (the real client, the real verb) answers on it.
- **P4** host service sockets: `/var/run/docker.sock`, the systemd bus env var if present,
  `/run/user/1000` — connect refused or stat denied.
- **P5** launcher and helper sockets from the design §1 table: refused.
- **P6** the reach scan: `~/.ssh`, `/etc/shadow`, the secrets root, `/home`, host `/run/user`
  unreadable; `/proc/self/mountinfo` parsed: every rw bind source is inside A's own subtree,
  and no source names any path from B's registry entry; `stat` of the broker sock dir shows
  0700.
- **P7** the egress boundary: a direct TCP connect to (i) B's planned OpenCode port at its
  planned container IP (from the registry) and (ii) one closed port must time out or be refused
  within a bound; through the planned proxy, a non-allow-listed host must be refused; a
  `SKIP` line records the accepted-by-design external-network row (a2a §11 r10) as not-probed.
- **P8** env hygiene: `os.environ` keys ⊆ the planned env table — no `*_TOKEN`, no provider-key
  names (`grep` of `environ` keys, the values never printed).
- **P9** the token canary: a sentinel string the operator places in the project's env file
  before the run (`--canary SENTINEL`, default the registry's canary field if present; SKIP
  with instructions if absent) must be absent from the environment, `/proc/self/environ`, and a
  broker `list` answer.

## Unit tests (`tools/tests/test_a2_hostile_live.py`)

Import the module (pure functions: arg parsing, probe registry, emitter, the exit-code rule) and
also run it as a subprocess. Cover: all-PASS against a fake registry + a fake `docker` PATH shim
answering the host-side probes (exit 0, one line per probe, the SUMMARY line correct); one
injected FAIL (the fake says a socket answered) → the FAIL line, exit non-zero; `docker` missing
from PATH → dependency reported FAIL, no traceback; bad args (each of the exit-2 shapes) →
exit 2 and no probe lines; `--dry-run` → probe list printed, exit 0; the never-change-state rule
asserted **on the fake**: after any run, the shim's world JSON is byte-identical and it recorded
no `create`/`rm`/`restart`/`up` call. Free ports for the in-test listeners; temp HOME/XDG; the
tests never touch the real `/run/{project}` or any docker.

## The runbook (`docs/a2x-cutover.md`)

Sequence with commands: full gate green → run P1–P9 for every configured pair (owner's command
line, the stdin-injection form, plus the `--via-docker` variant) → the two manual spike-style
checks that change state (stop A's container, confirm `docker port` empty; `findmnt` from the
host for one container) → where to keep the transcript (the evidence dir; the SUMMARY line is
the cutover record). Fenced commands valid bash after placeholder substitution, the
`oc/tests/test_acceptance.py` doc-fence precedent.

## Acceptance criteria

1. `python3 tools/run_tests.py tools.tests.test_a2_hostile_live` passes (the `tools` suite is in
   `run_tests.py`'s SUITES; precedent `tools/tests/test_run_tests_tmp.py`).
2. The full gate passes; the anonymity gate sees no site values in the three new files.
3. `python3 tools/a2-hostile-live.py --dry-run --project a --other b --registry <temp fake>`
   runs in the sandbox and exits 0 printing the probe list — the **only** live-code path that
   works here; the worker states plainly that P1–P9 against a real container is the owner's
   cutover run (ruling 25).
4. Scope guard: changed files are exactly the three owned.

## Out of scope

Nothing under `broker/`, `hub/`, `oc/`, `launcher/`. No image change (no Dockerfile edit —
owner question 1's pick). No CI wiring: the script runs at cutover, not nightly.

## Notes (worker rules)

No git history commands; the harness commits. The sandbox has no docker binary at all, so the
fake PATH shim carries every host-side unit test; the stdin-injection path needs no docker and
its logic is importable. Run long suites detached (`setsid -f`). While working, run only your
module; the full gate once at the end — this is the chain's last step, so the full gate is its
verify too. Your verify (from `a2x-chain.json`) is the check the orchestrator trusts.
