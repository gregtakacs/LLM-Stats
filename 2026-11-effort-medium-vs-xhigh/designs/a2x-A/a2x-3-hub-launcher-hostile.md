# a2x-3 — hub relay + launcher hostile (gate layer)

## Goal

Close the gaps in `docs/specs/a2x-design.md` §"Step 3": the remaining router-shape attacks at the
hub (trailing dot, double-encoded traversal, reserved words on the project row in both cases,
foreign-project WebSocket, hand-planted `Api` belt) and the two hostile states at once at the
launcher. Two new modules: `hub/tests/test_a2x_relay_hostile.py` and
`launcher/tests/test_a2x_oc_hostile.py`.

## Read first

- `docs/specs/a2x-design.md` (ground rules; Step 3 gaps)
- `docs/specs/a2h-2-routes-relay.md` (rows and the X-list this step extends — do **not** re-type
  X1–X18 cases that exist), `docs/specs/a2h-design.md` §10
- `hub/tests/test_a2h_relay.py` (the gate-order harness: `assert_before_verifier`,
  `assert_untouched`, `send`, raw-socket style), `hub/tests/httputil.py`, `hub/tests/test_anonymity.py` (why every
  name here must be synthetic)
- `hub/routes.py` (`RESERVED_HOME_NAMES` line ~79, route table order, the `/p/` rows),
  `hub/projects.py` (registry read)
- `launcher/tests/test_oc.py` (docker-recorder fixture, lines 261–342 for the single-state cases
  this step composes), `launcher/oc.py` (`OcExecutor`, `ActionError` codes `unsafe_mount`,
  `oc_unavailable`, `unknown_project`, `failed`)

## Files owned

- `hub/tests/test_a2x_relay_hostile.py`, `launcher/tests/test_a2x_oc_hostile.py` (new)
- fix scope (only if a case proves a hole): `hub/routes.py`, `hub/projects.py`, `launcher/oc.py`
- `hub/tests/httputil.py`, `launcher/tests/util.py` — helpers may be **added**, none changed

## Contract

| case | expected | proven absent |
| --- | --- | --- |
| `/p/alpha./api/x` (trailing dot on a known project) | 404 `gate.BODY_404` — the router must not trim the dot into a hit | fake upstream untouched |
| `/p/%252e%252e/api/x` (double-encoded traversal) | 404 or 400 — pin which, per what accept-decoding does to `%252e` (it decodes to the literal string `%2e%2e`, which is not a dot-segment: expect **404**, a name miss, never a traversal); assert X1's 400 for the single-encoded forms is *not* triggered here | untouched |
| every reserved word on the project row, both cases: `/p/p/`, `/p/h/`, `/p/api/`, `/p/server/`, `/p/session/`, `/p/new-session/`, `/p/settings/`, `/p/assets/`, `/p/_assets/`, `/p/auth/` and `/p/Api/`, `/p/AUTH/` | 404 `BODY_404` (they are registry-misses for the router) — **and** none of them is served by the hub's *own* routes with project semantics (the hub's `/api/...` rows are its own surface and answer per their rows — the assertion is scoped to `/p/<word>/`) | untouched |
| hand-planted registry containing `{"Api": ...}` written straight to `projects.json` | the router still does not serve `/p/Api/` as a project row (404) — belt of ruling 8; if the route table *does* pick it up, the hole is in routes: fix by adding the `RESERVED_HOME_NAMES` case-insensitive check to the project-row matcher | untouched; `projects.json` the test planted is its own temp file |
| WebSocket upgrade `GET /p/<other-project>/api/pty/x/connect` with *valid* credentials for the requesting project | 404 before any `101`/handshake bytes (contrast X9/X10, which cover cross-site and hub-origin upgrades on one's *own* row) | no upgrade bytes on the wire; fake upstream untouched |
| launcher: bind source planted symlink **and** wrong container label at once | `ActionError` `unsafe_mount` (mount check first — pin the code order from `launcher/oc.py`), one audit line naming the caller | recording docker: zero `start`, zero `stop` |
| launcher: registry swapped between name-lookup and start inside one action (the recorder's inspect answer changes mid-call) | the action uses the snapshot it validated (documented behaviour) or refuses — read `launcher/oc.py`'s read pattern; pin whichever the code guarantees, and if it re-reads and then starts the *new* target without re-validating mounts, that's a hole: fix by validating the same snapshot the start uses | no `start` of a container that was not validated |

## Behaviour and edge cases

- Hub cases reuse the raw-socket `send`/`ws_connect` harness of `test_a2h_relay.py`; statuses are
  checked byte-level against `gate.BODY_*`. No new gate codes, no new routes.
- The planted-registry case must go through the hub's *file* read path (write the JSON the same
  way `hub/tests/httputil.py::write_projects` does — with `Api` added), not a monkeypatched dict.
  If `write_projects` refuses reserved names (helper validation), that itself is coverage: then
  the belt case asserts the helper-level refusal **and** the router case for `alpha.` etc. stands
  alone. Read the helper first; adapt; do not weaken it.
- Launcher cases drive the existing recorder fixture; the swap case needs the docker recorder to
  answer two different states on consecutive calls — extend the recording fake (additive) if it
  only supports static answers.
- All host names/cookies/sessions synthetic; `test_anonymity.py` runs the hash check over the
  suite, so real domains/addresses must not appear in any new file.

## Acceptance criteria

- `python3 tools/run_tests.py hub.tests.test_a2x_relay_hostile launcher.tests.test_a2x_oc_hostile`
  → `ok`; full gate once at the end; `test_a2h_relay.py`, `test_oc.py`, `test_anonymity.py`
  unchanged and green.
- Holes fixed in-component, same commit, inside the fix scope.
- Scope guard: only Files owned touched.

## Out of scope

Broker, oc, tools; authentication/session plumbing (A1/A2 own it); the live hub probe (step 4);
no new HTTP codes.

## Notes for the worker

The point of the reserved-word row is a *statement about cases*: the broker guard is
case-insensitive, the hub route table is byte-exact — your job is to pin that the composition
cannot serve a reserved name in any spelling at any layer you own. If two layers disagree in a
way that needs a product decision, `STATUS: blocked` with the exact pair.
