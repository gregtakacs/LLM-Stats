# a2x-3 — Planner / installer / migration hostile suite: the bind list is the boundary

**Goal.** Prove A2's mount promise from the generation side: hostile input never gets a hostile
path *into* a planned container, the generated argv contains none of the takeover flags, the
installer refuses before it creates (and refuses loudly, leaving the fake docker's world
untouched), and migration cannot be steered by hostile session content. This is design
`docs/specs/a2x-design.md` §5.3 (cases XO1–XO9, XI1–XI3): the delta over `oc.tests.test_projects`
and `test_projinstall`, which already check the planner's refusals one component at a time.

**Read first.** `docs/handoff.md`; `docs/specs/a2x-design.md` §1–§4, §5.3, §8; the specs whose
contracts you assert: `docs/specs/a2-design.md` §5 (the container's shape) and §9 (migration,
with the ruling quoted there), `docs/specs/a2i-5-migrate.md`; the existing coverage you must not
duplicate: `oc/tests/test_projects.py`, `test_projinstall.py`, `test_install.py`,
`test_migrate.py`. Then the code under attack: `oc/projects.py` (`binds`, `plan_project`,
`create_argv`, `network_argv`, `egress_argv`, `PlanError` keys `home`/`projects.<P>`/
`secret-file`/`mount`/`subnet-pool`, the constants `CONTAINER_PREFIX`, `EGRESS_NAME`,
`LABEL_PROJECT`, `MOUNT_BAD_CHARS`, `OC_PORT`), `oc/projinstall.py` (phases, refusals,
`Failure`), `oc/migrate.py` (`REASONS`, exit codes 0/1/2, `MAX_SOURCE_BYTES`,
`MAX_PAYLOAD_BYTES`), `oc/install.sh` (the `projects` verb path), and `hub/projects.py` +
`broker/config.py` for the one-name-three-doors case. Your fixtures: `broker.tests.util.Fixture`
with `groups=` (the two-project shape `test_projects` already uses), and the PATH `docker`
**recording shim** pattern from `oc/tests/test_projinstall.py` — reuse its technique (a Python
shim on PATH logging every argv to `shim.log` over a mutable JSON world).

**Files owned.** `oc/tests/test_a2x_planner_hostile.py` — the only file you create. **Fix
scope** (only on a real defect, narrowest change): `oc/*.py`, `oc/install.sh`. FINDING-precedent
commit messages; contract changes are reported, not made.

## Contract table (the expectations you assert — cited, not invented)

| Fact | Source |
|---|---|
| the bind list is the container's whole reach: own members, own worktree root, own broker sock dir, own secret files — nothing else, ever | `oc/projects.py:binds` (line 201), design a2 §5 |
| members whose path docker could not take (comma/quote/newline/NUL in it) are refused as mounts with key `mount`; the `$HOME`/data-root/registry-dir *overlap* refusals are `install.sh`'s and `projinstall`'s, not the planner's — assert them at the door that actually shuts them | `projects.py:_check_mount_value` (`projects.py:172-184`), `MOUNT_BAD_CHARS` (`projects.py:57`), `test_install`/`test_projinstall` precedents |
| `secret-file` shape: an absolute path or `PlanError`; the **mode** 0400–0600 check is the installer's and preflight's job (`install.sh` refuses a 0640 file; projinstall refuses before create) | `projects.py:241`, `oc/install.sh`, `test_install` matrix |
| network: `/28` IPv4 only; `--internal`; the egress container name and proxy host must be names docker would take; the create argv carries **no publish flag at all** | `projects.py:create_argv/network_argv/egress_argv` (lines 441-466), `test_projects` precedents |
| project name rules are one set at every consumer: `SEGMENT_RE`/`_project_name_ok` (`hub/projects.py:41,190`), `RESERVED_PROJECT_NAMES` (`broker/config.py:55`, checked case-insensitively at `config.py:319`), `CONTAINER_PREFIX`+sha16 | as cited; the prefix trap `web` vs `web-app` is broker `test_paths`/`test_targets` precedent |
| installer refusals write nothing and create nothing: every generated file passes `site_values_in`; secret modes exact (0600 trio / 0400 project files), password printed nowhere; a planted symlink at a worktree root is a refusal before create; a foreign `{project}-oc-*` container is never touched | `oc/tests/test_projinstall.py`, `test_install.py` (the installer half) |
| migration lands a session only in its own project's store or refuses with a reason from `REASONS` (`migrate.py:51-53`); exit 0/1/2; hostile *content* (title, cwd strings inside the payload) can never steer a *path*; oversized source refused before parsing (`MAX_SOURCE_BYTES` = **100 KiB**, the helper source cap, `migrate.py:40`; `MAX_PAYLOAD_BYTES` = 64 MiB, `migrate.py:43`); content never echoed to stdout/stderr | `oc/migrate.py`, spec a2i-5 |
| the fake docker's world is the side-effect oracle: after every refusal its JSON is byte-identical, and its log shows no `create`/`rm` line for the refused input | the `test_projinstall` shim + `util.docker_state` pattern |

## Behaviour and edge cases

Your test list is design §5.3 XO1–XO9, XI1–XI3, one method per case, the id in the docstring.
Class layout: `MountHostiles` (XO1–XO4, XO7 — the reach scan asserts every host path of the
threat table appears in **no** bind/argv/env entry, for A and for B), `ArgvWall` (XO5, XO6 — the
forbidden-flag scan runs over the planner's *returned* argv and, for the create path, over the
recorded shim call), `InstallerRefusals` (XO8, XO9), `MigrationHostiles` (XI1–XI3, injected
in-memory `FakeDocker` like `test_migrate` so content-level attacks cannot shell anything out).
For XO3 (one name, three doors) call the three consumers in-process (`hub.projects`,
`broker.config`, `oc.projects`) with the same hostile string and assert each refuses in its own
shape, without echoing the value. For XI1's "valid session with hostile title" half: a real
export JSON whose *title* is `../../etc/passwd` and whose cwd field is inside **A's** tree must
import into A's store only (title is data); the same content with a cwd naming **B** must be
refused or land nowhere, per `REASONS`/`verify_failed` — follow what `migrate.py` actually does
and assert that, citing the reason in the test.

## Acceptance criteria

1. `python3 tools/run_tests.py oc.tests.test_a2x_planner_hostile` passes; every XO/XI case named.
2. The full gate passes, including the anonymity gate (`site_values_in` on every generated file,
   and no site values in the module itself).
3. Scope guard: changed files ⊆ the owned one, plus fix-scope `oc/*` only if a FINDING commit
   message names them.
4. The module sets `HOME`/`XDG_*` into its temp dirs, uses explicit modes (host umask is 002),
   and never touches the real `~/.local/share/{project}/` or `~/.config/{project}/`.

## Out of scope

No broker or hub file; no `tools/` file (that is a2x-4). No new fakes — reuse `util`'s and the
projinstall shim. No re-typing of `test_projects`/`test_install`/`test_migrate` happy paths.

## Notes (worker rules)

No git history commands. The sandbox has no docker binary — the shim *is* the docker here, and
that is exactly what ruling 26 permits (fake for docker/git/gh, never for the planner or the
installer under test). `install.sh` runs as a subprocess with a scrubbed env, mirroring
`test_projinstall`. Run long suites detached (`setsid -f`). While working, run only your module;
the full gate once at the end. Your verify (from `a2x-chain.json`) is the check the orchestrator
trusts; do not substitute a narrower one.
