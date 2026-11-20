# a2x-4 — the live container probe script (`tools/a2-hostile-live.py`)

## Goal

Build the second layer of ruling 26: one stdlib-only host script that runs the 12 probes of
`docs/specs/a2x-design.md` §"Step 4" (the design's item 5 splits into two probes) against real
running containers **read-only**, printing
`PASS/FAIL/SKIP` lines, plus a gate-tested fake-docker harness proving the script's own logic.
Ruling 26 and the sandbox rules mean **no worker ever runs the live thing**; the gate proves the
harness, and the closing report must carry `LIVE PROBE RUN: NOT VERIFIED`.

## Read first

- `docs/specs/a2x-design.md` (ground rules; the probe list; never-change-state rule; Owner Q2/Q3)
- `docs/specs/a2-design.md` ruling 26, §10
- `tools/tests/test_run_tests_tmp.py` (the `tools.tests` module conventions), `tools/run_tests.py`
  (the `tools` suite already exists)
- `broker/client.py` (what the in-container `worktree_cross` probe runs and its exit-125/69 +
  one-line stderr contract), `oc/projects.py` (`CONTAINER_PREFIX`, `OC_PORT`, `BROKER_SOCK_IN`,
  label names), `broker/paths.py` (`sock_path` — the socket layout probe 1 stats), the fake
  `docker` in `broker/tests/fakes/docker` (world-model of what `inspect`/`ps`/`exec` must look
  like for the canned answers to be honest)

## Files owned

- `tools/a2-hostile-live.py` (new)
- `tools/tests/test_a2_hostile_live.py` (new)
- nothing else. A probe that would need a product change means the product is wrong — report it;
  do not fix it here.

## Contract

CLI (argparse, stdlib only):

```
python3 tools/a2-hostile-live.py --project A --other B [--dry-run] [--socket PATH]
                                 [--require-hub] [--allow-mount-home] [--allow-mount-run-user]
```

- `--project` and `--other` both required (no default): cross-project probes need a second real
  project to point at. Names validated against `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$` — hostile
  names can't reach the shell (subprocess is always argv-list, `shell=False`, everywhere).
- Preflight: `docker ps` (argv list) must show containers for both projects (label
  `{project}.oc.project`); otherwise print `not-running: <details>` to stderr, exit **2**, zero
  `docker exec` calls made.
- Output: one line per probe, `PASS <name>` | `FAIL <name>: <one-line detail>` |
  `SKIP <name>: <why>`; then `SUMMARY: pass=N fail=N skip=N`; exit 0 iff fail=0 (SKIPs do not
  fail unless `--require-hub` and a hub probe skipped).
- `--dry-run`: print the probe plan (`PLAN <name>: <exact argv>`) and exit 0 without executing.
- **Effect primitives, closed list:** `docker ps`, `docker inspect`, `docker exec <container>
  <argv>` with `<argv>` from the script's `PROBE_ARGV` builder — every argv the script can
  produce must appear in the dry-run plan, and the unit test asserts every recorded exec argv
  matches the recorded dry-run plan for the same probe (the allow-list *is* the dry-run). `cp`,
  `rm`, `run`, `start`, `stop`, `push`, `kill` are unreachable by construction.
- Probes 1–11 exactly as the design lists them (names: `socket_perms`, `oc_port_bound`,
  `data_dirs_cross`, `worktree_cross`, `egress_block`, `lan_side`, `docker_socket`, `run_user`,
  `launcher_socket_absent`, `token_file`, `home_ssh`, `hub_prefix_mismatch` — `egress_block` and
  `lan_side` are two probes: 12 lines total). The in-container connect helper is
  `python3 -c` with a fixed source string (socket connect / CONNECT-verb request); its source is
  a constant in the script so the allow-list assertion can pin it byte-for-byte.

## Behaviour and edge cases (unit-tested, fake `docker` first on PATH)

1. `--dry-run`: no exec recorded, exit 0, plan lists every probe with exact argv.
2. Preflight fail: fake `ps` without the labels → exit 2, zero execs.
3. Happy grid: canned inspect JSON (two projects, mounts as `oc/projects.py` builds them) +
   canned exec exit codes per probe → all `PASS`, exit 0; the recorded exec argvs ⊆ dry-run plan
   argvs (this is the never-change-state proof at harness level).
4. Per-probe FAIL wiring: each probe in turn answered "isolation broken" (e.g. `test -e
   /var/run/docker.sock` exits 0) → exactly that probe `FAIL`, exit 1, detail line carries the
   probe's documented meaning (one line, no argv echo of secrets).
5. `SKIP` wiring: hub absent → `hub_prefix_mismatch` SKIPs; `--require-hub` flips it to FAIL;
   `--allow-mount-home`/`--allow-mount-run-user` flip probes 7/10 to SKIP with the warning text.
6. Token discipline: `token_file`'s host-side stat is on the configured path; the in-container
   env check greps case-insensitively for `{project}_gh_token`, `gho_`, `ghp_` and the **detail
   line must not echo the matching environment entry** (name only, never value).
7. Bad `--project` name (`;rm -rf /`, leading dash, 65 chars, empty): argparse-level refusal,
   exit 2, zero docker calls.
8. Unicode/bidi in the other project's name never reaches argv unvalidated (same rule as 7).
9. The script is importable (`if __name__ == "__main__"`) and takes an injectable `run` for the
   tests, mirroring `oc/migrate.py`'s pattern.

## Acceptance criteria

- `python3 tools/run_tests.py tools.tests.test_a2_hostile_live` → `ok`; full gate once (this is
  the chain's last step).
- `python3 tools/a2-hostile-live.py --dry-run --project A --other B` runs on the host **without
  docker** and exits 0 with the plan (dry-run must not preflight-exec — check argv plan only).
- Scope guard: only the two Files owned touched.
- Report states `LIVE PROBE RUN: NOT VERIFIED` verbatim (ruling 26).

## Out of scope

Any product-code change; CI wiring for the live run (the owner runs it at cutover); probes beyond
the named 12; state-changing "cleanup" anything.

## Notes for the worker

The fake docker in `broker/tests/fakes/docker` is the reference for honest canned shapes, but
your fake lives inside `tools/tests/test_a2_hostile_live.py` (or a sibling helper module) since
the `tools` suite shouldn't import `broker.tests`. Keep it single-purpose: record every argv,
answer from a per-test dict, raise on anything outside the dry-run plan (fail-closed — a probe
that invents an effect must blow up loudly in the gate, not pass).
