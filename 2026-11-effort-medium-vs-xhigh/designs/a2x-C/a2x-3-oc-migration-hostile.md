# a2x-3 — oc planner and migration hostile suite (in-process)

## Goal

Write `oc/tests/test_a2x_oc_hostile.py` covering design §7's cases AX-P1..P6 and AX-M1..M7:
hostile project records through `oc.projects` (plan → `create_argv`, scanned token by token) and
hostile session exports through `oc.migrate`'s real functions with the fake-docker executable on
`PATH` (via `broker/tests/fakebin.py` from step 1), so no record or document can steer a mount, a
path, or a byte outside its own project's store.

## Read first

`docs/specs/a2x-design.md` §7, §9, §11; `oc/projects.py` (module docstring = the mount contract;
`NAME_RE`:48, `_check_mount_value`:174-186, `_check_not_trusted`:188-196, `binds`:201-249,
`plan_project`:363+, `create_argv`/`_create_body`, `network_argv`, the import of
`daemon.config._name_ok` at 858-862); `oc/migrate.py` (`REASONS`:51-53, `Usage`:56+, the
export/import flow, `_contained_by`/`_assign_project`, the store write path);
`oc/tests/test_projects.py` and `test_migrate.py` (how they build configs, fake docker, and a
`Layout` — reuse, don't re-fake); `docs/specs/a2h-design.md` §5 (planner shape), §9 (migration);
`docs/specs/a2-2a-broker-core.md` for the export wire document's shape.

## Files owned

- `oc/tests/test_a2x_oc_hostile.py` (new)
- (fix allowlist, only if a case fails: `oc/projects.py`, `oc/migrate.py` — named before the fix)

## Contract

- Every P case asserts on the *argv list* `create_argv(plan)` returns (and `network_argv`), never
  on the plan object's private fields: a hostile value either raises `PlanError` whose `where`/
  message names the key and not the value's tail (`_brief` rule), or the argv is scanned to show
  the hostile path is absent and the project's own subtree is the only thing mounted from that key.
- The `create_argv` pin list (AX-P6), read from the current `_create_body` at write time and
  asserted for every plan this suite builds: `--cap-drop ALL`, `--security-opt no-new-privileges`,
  `--read-only` where the design keeps it, `--user <project uid>`, the loopback-published 4096
  mapping (`127.0.0.1:` prefix — cite the argv), the `/28 --internal` project network, the broker
  sock dir mounted `ro`, and **no** occurrence of `~/.ssh`, `/run/user`, `docker.sock`, any
  other project's name, or a token path anywhere in any argv token.
- Every M case drives the real migrate entry path with a fake `docker` (fakebin) that replays the
  export JSON from the test; expected outcomes are the `REASONS` names only — assert the refusal's
  reason field equals one of the documented values (migrate.py:51), never a substring of free text.
- The store invariant, asserted after *every* M case with an `os.walk` of the whole fake home
  tree: files exist only under the claimed project's session store directory; nothing at or above
  its parent; zero writes outside the temp root (the tree root is the test's temp dir — a find for
  mtimes newer than the case start outside it is the assertion).
- AX-M6 partial failure: nine carried, two refused, and the summary the run prints is checked for
  both refused session ids and nothing else (id echo is allowed — ids are data the caller supplied;
  content is never echoed).
- Dual-mode run per design §9; free ports none needed here (no sockets bound).

## Behaviour and edge cases

Design §7's table verbatim, one method per id. AX-P2's sibling-prefix case must *pass* planning
(both projects real) and be disjoint — the assertion pair: both plans produce, and neither argv
contains the other's data root token. AX-P4 asserts subnet reuse is by-design (`//16` shape per
planner docs) but network *names* stay per-project. AX-M3's byte-exactness: after import, read the
stored session file and compare to the source doc's field byte for byte.

## Acceptance criteria

- `python3 tools/run_tests.py` fully green; `ok oc.tests.test_a2x_oc_hostile` present.
- No test writes outside its temp root in either mode (proven by the walk assertion, which fails
  the test if not).
- Scope guard: only owned files (plus a fix, if forced, named above).

## Out of scope

The broker socket layer and the relay (steps 1, 2); the live script (step 4); `entrypoint.sh` and
`oc/bin/*` behavior under hostile env (owned by earlier a2h steps; this suite cites their tests
rather than duplicating); daemon code entirely.

## Notes

`REASONS` has exactly ten names; a case that produces an undocumented crash (traceback escaping the
CLI's error contract) is a component bug — fix under the allowlist, one sentence here first.
