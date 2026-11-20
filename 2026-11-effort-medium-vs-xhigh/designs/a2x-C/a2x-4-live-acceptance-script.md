# a2x-4 — the live acceptance script and its unit tests

## Goal

Write `tools/a2-hostile-live.py` (stdlib-only host script implementing design §8's container-layer
probes) and `tools/tests/test_a2_hostile_live.py` (its gate-side unit tests against a fake `docker`
executable). The script is run once, by the owner, against two live projects at cutover; its tests
run in every gate. **A worker cannot run it for real here: the sandbox has no Docker socket — unit
tests against the fake are the worker's whole verification, and the real run is listed under "at
cutover" below.**

## Read first

`docs/specs/a2x-design.md` §8, §9, §11; `oc/projects.py` (`load_registry`:808+ — the only legal
way to read the project list; `registry_path`:122; `EGRESS_NAME`/`OC_PORT`/layout keys from
`layout()`); `launcher/oc.py` header (how the launcher treats the registry as host truth);
`broker/tests/fakebin.py` (step 1's helper — the unit tests reuse it); `tools/tests/` (suite shape);
`docs/handoff.md` §on test policy.

## Files owned

- `tools/a2-hostile-live.py` (new)
- `tools/tests/test_a2_hostile_live.py` (new)

## Contract

CLI (argparse, no dependencies beyond stdlib + `oc.projects` importable in-repo):

- `a2-hostile-live.py --project A --other B [--dry-run] [--json] [--echo-url URL]`;
- refuses **before touching docker** unless both names load from the registry through
  `oc.projects.load_registry(oc.projects.registry_path(...))` (exit 2, one line, names the key not
  the value); `--dry-run` prints the probe plan as JSON (ids, argv, expected) and exits 0;
- every probe command goes out as `docker exec --user <the container's own user> <container> …`
  argv list, never a shell string, never `--privileged`, never `docker create/start/stop/rm` —
  the **never-change-state rule** (design §8): read/connect/refused-request only; container-side
  writes only under `/tmp` via a probe's own `mk`+cleanup, and any probe that cannot promise that
  prints `SKIP <id> <why>`;
- output: one `PASS <id>` / `FAIL <id> <expected vs observed, one line>` / `SKIP` line per probe on
  stdout, diagnostics on stderr, exit 0 iff no FAIL (SKIPs don't fail the run — the owner reads
  them), exit 1 on any FAIL, exit 2 on usage/registry/docker-missing (a documented "docker not on
  PATH" line, never a traceback);
- probes implemented exactly as design §8's table (AX-X1..X5, AX-E1..E5, AX-S1, AX-S3, AX-X7,
  AX-X8); B-side ip/paths come from the registry's own fields + the documented `/28` layout, never
  re-derived by guessing; AX-S1 sends only to `--echo-url` when given and SKIPs otherwise;
- module docstring states the cutover contract: run order (owner starts A and B first), and that a
  FAIL on AX-X7/AX-X8 is escalate-to-owner, not code-fix territory (a2-design §9).

Unit tests (fake `docker` from fakebin on PATH, temp HOME with a real registry file written by the
test at 0600 owned-by-us via `projinstall`-shaped content — or `load_registry`'s fixture pattern
from oc tests):

1. all-pass replay → exit 0, `PASS` line per probe id, registry guard recorded zero argv before
   the guard passes;
2. one replayed FAIL → exit 1, exactly that `FAIL` line;
3. docker absent (PATH stripped) → exit 2 with the documented line;
4. `--dry-run` → valid JSON, every probe present, fake docker recorded nothing;
5. missing/unknown `--project` or `--other` → exit 2, zero docker argv recorded;
6. **structural state rule**: across all four scenarios, every argv ever recorded is scanned for
   forbidden tokens (`rm`, `stop`, `restart`, `kill`, `>`, `tee`, `--privileged`, non-`exec` docker
   verbs) and a violation fails the test — this is the rule made executable;
7. `--user` on every exec equals the registry's container user (the fake records env+cwd too —
   assert no host env secret rode in).

## Behaviour and edge cases

Replays must cover each probe's three classes: expected-refusal replayed as *allowed* → FAIL;
expected-allowed replayed as refused → FAIL; probe script missing inside (exit 126/127 replay) →
FAIL with "probe binary absent", never SKIP. Unicode project names can't reach the registry
(`load_registry` refuses), so the CLI guard test feeds a 0644 registry instead → exit 2 naming key
`registry`.

## Acceptance criteria

- `python3 tools/run_tests.py` fully green (both suites); `ok tools.tests.test_a2_hostile_live`
  present.
- `python3 tools/a2-hostile-live.py --dry-run --project A --other B` exits 2 in the worker's
  sandbox for the registry reason and prints the one documented line (the worker DOES run this).
- Scope guard: only the two owned files.
- **At cutover (owner, not worker):** start projects A and B, run the script, read every FAIL/SKIP.

## Out of scope

Any gate-time docker execution; changing the container shape the probes assert (findings go to the
owner per a2-design §9); the picker UI (step 7); CI plumbing.

## Notes

Keep the script single-file, under ~600 lines; probe registry as a list of dataclass rows so
`--dry-run` and the scanner read the same table the exec path uses — no second source of truth.
