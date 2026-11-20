# a2x-2 — install plan, migration, egress hostile (gate layer)

## Goal

Close the four gaps in `docs/specs/a2x-design.md` §"Step 2": hostile *values* through the planner
composed (`validate` → `build_plan`), the double-planted-link apply composition, the migration
session source treated as untrusted input, and the plan-level LAN-pin absence. Two new modules:
`oc/tests/test_a2x_plan_hostile.py` and `oc/tests/test_a2x_migrate_hostile.py`.

## Read first

- `docs/specs/a2x-design.md` (ground rules; the Step 2 gap list)
- `docs/specs/a2-design.md` §9 (migration, the no-delete rule), §10 rows "Installer follows
  planted link", "Migration exports"
- `docs/specs/a2a-design.md` §11 rows 31/32 (the already-closed single-state cases)
- `oc/projects.py` (`PlanError`, `validate`, `build_plan`, `_image_or_refuse` line ~332,
  `pin_hosts`, `egress_argv`, the env builder), `oc/projinstall.py` (apply, the planted-link
  refusals), `oc/migrate.py` (module docstring, `REASONS` line ~51, `run_main`, the injected
  `run`), `oc/sessions.py` (`_exported`, `_import`)
- `oc/tests/test_projects.py`, `oc/tests/test_projinstall.py` (fixture style to copy —
  especially the two planted-symlink cases at lines 511/526), `oc/tests/test_migrate.py` (the
  injected-`run` recorder style — there are 53 cases there already; copy the harness, add none
  of their cases)

## Files owned

- `oc/tests/test_a2x_plan_hostile.py`, `oc/tests/test_a2x_migrate_hostile.py` (new)
- fix scope (only if a case proves a hole): `oc/projects.py`, `oc/projinstall.py`,
  `oc/migrate.py`, `oc/sessions.py`, `oc/install.sh`
- `oc/tests/util.py` — helpers may be **added**, none changed or removed

## Contract

No new public surface. Shapes come from the code:

| case | expected (cite in test comment) | side effect proven absent |
| --- | --- | --- |
| mount source is a symlink under the projects root | `PlanError` key `mount`, message = the planner's refusal sentence for that key | fake docker records zero calls; no write through the link (checked at its true target) |
| secret file is a symlink | key `secret-file` | nothing read through — the error text names the project's secret-file key, never the target path (refusals don't leak paths; ruling: error messages name keys not contents) |
| providers file is a symlink / has a duplicate key | key `providers-file` | zero docker calls |
| project named `Api`/`p`/`_assets` (reserved, both cases) | refused through the composed path: broker config already refuses case-insensitively (`broker/config.py:319`); a *hand-planted registry* read by `oc/projects.py::load_registry`/`validate` must not get a container either — pin the refusal (`projects.<P>` key or `load_registry`'s documented refusal). If any reserved word in any case passes both gates, that's the hole: fix by comparing `name.lower()` against `broker.config.RESERVED_PROJECT_NAMES` at the gate that leaked (oc already imports broker.config — `oc/projects.py:34`) | zero docker calls |
| egress allow entry `*`, `host:443`, `host name` (space) | refused by `egress_argv`/`pin_hosts` rules — pin the exact key+sentence the code produces | no create argv emitted |
| image ref with a space / metacharacters / missing tag | `_image_or_refuse` → `PlanError("image", "<brief> is not an image name")` (`oc/projects.py:339`) | zero docker calls |
| double-planted links at apply (worktree root AND a home mount point, both symlinks to dirs with sentinel files inside) | apply exits non-zero; the output names one deterministic refusal (first in the documented check order — read `oc/projinstall.py` apply's order and pin that order) | sentinel files in both true targets unchanged (byte compare) |
| migration: hostile source answers (see below) | one `REASONS` member per case, verbatim from `oc/migrate.py:51` | the injected `run` recorder proves: no exec verb outside `{list, export, import, count}` (the docstring's allow-list), no `rm`/`-d`/delete-shaped argv anywhere, no host write outside the report file |
| migration: payload over `MAX_SOURCE_BYTES` (100 KiB) | reason `too_large` for that session; others proceed | import not attempted for it |
| migration: answer is not JSON / has NaN | `export_failed` (parse class per `_exported`); run continues | as above |
| migration: count mismatch at verify | `verify_failed`; the shared source's session untouched afterwards (source `count` re-run answers same number) | no delete exec |
| migration: destination already has it | `existed`, counted as success, no re-import | recorder shows one import per session at most |
| plan with resolver answering `10.0.0.5` / `127.0.0.1` / `169.254.169.254` for an allow-listed host | plan builds (hosts allowed by name) but **no `--add-host` line carries a non-public address**; `HTTPS_PROXY` forced to the egress container; `NO_PROXY` exactly `localhost,127.0.0.1,::1` whatever config claims | fake docker create argv contains no RFC1918/loopback/link-local pin |

## Behaviour and edge cases

- Planner cases drive `validate`+`build_plan` composed (config dicts on hostile values, temp
  HOME/XDG set, explicit modes), never the private helpers directly.
- Migration cases drive `run_main` with an injected `run` (the existing pattern in
  `test_migrate.py`); the fake answers stand for a hostile shared container. Titles/ids/dirs
  with control chars, newline, leading `-`, 10k chars: the *invariants* are argv-as-list (every
  field appears as exactly one argv element in the recorded docker exec call, shell=False) and
  containment (nothing written outside the report path and the data dir). Pin the documented
  reason class per case; do not invent new reasons.
- The double-plant apply case must be deterministic: read `oc/projinstall.py` to find which
  planted-link refusal fires first in code order and pin **that** one, with a comment; if the
  code's order is nondeterministic (dict iteration), that's a hole — fix by iterating the sorted
  mount list.
- Egress composition: use the existing resolver-mock seam in `oc/tests/` (find how
  `test_projects.py` mocks DNS and reuse it).

## Acceptance criteria

- `python3 tools/run_tests.py oc.tests.test_a2x_plan_hostile oc.tests.test_a2x_migrate_hostile`
  → `ok`; full gate green once at the end; `oc.tests.test_projects`, `test_projinstall`,
  `test_migrate` unchanged and green.
- Holes found are fixed in the component, same commit as the test, inside the fix scope.
- Scope guard: only Files owned touched.

## Out of scope

`broker/`, `hub/`, `launcher/`, `tools/`; the *runtime* egress proxy behaviour (A2E's squid
config — this step pins only what the **plan** hands the container); real docker (none in the
sandbox).

## Notes for the worker

Iterate on your two modules through `tools/run_tests.py`; full suites once at the end. The
migration recorder is the point of the exercise: your `run` fake must fail-closed on any
forbidden argv (raise, don't ignore) so a regression can't sneak past.
