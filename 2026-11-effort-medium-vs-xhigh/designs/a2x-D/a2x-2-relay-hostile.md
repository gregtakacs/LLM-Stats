# a2x-2 — Hub relay hostile suite: cross-project at the HTTP seam, plus the accept boundary

**Goal.** Prove that at the relay the *raw path segment* is the only thing that picks a project,
that a credential never crosses projects, that claimed identity in headers changes nothing, and
that in projects mode the hub still answers only the networks it plans. This is design
`docs/specs/a2x-design.md` §5.2 (XR1–XR15) and §5.4 (XA1–XA3): the cross-component half the
per-component `test_a2h_*` suites structurally cannot see (plus the X25 wake race re-fought at
the relay seam — its only prior proof is launcher-side).

**Read first.** `docs/handoff.md`; `docs/specs/a2x-design.md` §1–§4, §5.2, §5.4, §8; the relay
table you extend rather than duplicate: `docs/specs/a2h-design.md` §10 (X1–X25 — X1–X24 are
already delivered in `hub/tests/test_a2h_relay.py`/`test_a2h_routes.py`; do not re-type them);
`docs/specs/a2a-10-hostile.md` for the hostile-suite style and its worker-rules block. Then the
code under attack: `hub/routes.py` (`_project_api` the byte-for-byte matcher at line 197, the
`/p/` rows), `hub/proxy.py` (`PROJECT_DROP` line 102, `request_headers_for` from line 325, the
forwarded pairs at 363–366), `hub/__main__.py` (`address_is_refused`, line 216 — the handler
checks the peer address, no header), `hub/projects.py` (`SEGMENT_RE` line 41, `_project_name_ok`
line 190),
`hub/adminapi.py` (the `no_login` → 409 mapping in `ERROR_STATUS`, line 55), and
`broker/config.py:55` (`RESERVED_PROJECT_NAMES` — the shared reserved set). Your harness is
`hub/tests/httputil.py`: read `HubTestCase`/`ProjectDoorTestCase`, `write_projects`,
`FakeOpenCode` (`last`, `header()`, `ws_handshakes`, the per-project password), `raw_request`,
`read_head` before writing a line.

**Files owned.** `hub/tests/test_a2x_relay_hostile.py`, `hub/tests/test_a2x_accept.py` — the
only files you create. **Fix scope** (only if a case finds a real defect, narrowest change):
`hub/*.py`. FINDING-precedent commit messages; contract changes are reported, not made.

## Contract table (the expectations you assert — cited, not invented)

| Fact | Source |
|---|---|
| the project is the **raw** segment; names match byte-for-byte, never decoded, never case-folded; any miss is the generic 404 | `routes._project_api` (`routes.py:197-208`), `test_a2h_routes` precedent |
| cross-project cookie → 401 before anything else; a project gets only its own Basic credential (per-project passwords from the registry) | `routes.py:197`, `proxy.request_headers_for` (`proxy.py:325`) |
| `auth_token` never forwarded; `Cookie` dropped; `X-Forwarded-Proto`/`-Host` written by the hub, not copied | `proxy.PROJECT_DROP` (`proxy.py:102`), the forwarded pairs at `proxy.py:363-366` |
| the target part is forwarded verbatim (the relay's whole promise): dot-segments inside the target reach the target unchanged | `routes.py:325` (`_forward_target` on row P6), relay X6 delivered test |
| reserved names can never be projects; the set lives in `broker/config.py` (`RESERVED_PROJECT_NAMES`) and is enforced by `hub/projects.py` (`_project_name_ok`) and again in the row matcher | both files, as cited |
| upgrade path: gate before dial (401 with no cookie / wrong cookie → the FakeOpenCode never sees a handshake) | gate-before-dial in the rows/gate design, `test_a2h_relay` X5/X7 precedents |
| declared body over the row cap → 413; bad framing (chunked+CL, obs-fold, CR-in-value) → 400/501 class, connection closed | a2h X11/X12 delivered tests (`test_a2h_relay`) |
| accept boundary: a connection from a refused source gets **zero bytes**, the verifier never hears; `X-Forwarded-For` is never consulted for the accept decision | `hub/__main__.py:154,216` (`address_is_refused` — the handler checks the peer address, no header), `test_a2h_accept.py` (all of it) |
| X25: the launcher answers the second serialized start `no_login`; the hub maps it to 409, and no wake happened | `ERROR_STATUS` (`hub/adminapi.py:50-55`), `test_admin_api.py:375` (the status half), `launcher/tests/test_dev_projects.py:533` (the race half) |

## Behaviour and edge cases

Your test list is design §5.2 XR1–XR15 and §5.4 XA1–XA3, one test method per case, the XR id in
the docstring. Class layout: `CrossProjectCredentials` (XR1, XR2, XR7), `NameSpellings`
(XR3, XR4, XR11, XR15 — the three-door control where the *same* hostile string is refused by
relay 404, broker `ConfigError`, planner `PlanError`; the last two via the in-process consumers,
not the network), `HeaderIdentity` (XR5, XR6), `TargetVerbatim` (XR8), `FramingAndLimits`
(XR9, XR10, XR13), `Concurrency` (XR12, XR14). For XR12 mix A and B requests concurrently and
assert each fake upstream's `last` belongs to its own project. XR14 drives two concurrent
project logins through the real hub against a `FakeLauncher` that serializes and answers the
second `no_login`, asserting 409, exactly one start line, and that B stayed quiet. For §5.4:
follow `test_a2h_accept.py`'s real-socket technique in projects mode (registry with alpha/beta
and their planned subnets); if binding the alias is impossible in the sandbox, use its `from_fd`
seam — owner question 4's pick — and say which path ran in the module docstring.

## Acceptance criteria

1. `python3 tools/run_tests.py hub.tests.test_a2x_relay_hostile hub.tests.test_a2x_accept`
   passes; every XR/XA case is a named test citing its id.
2. The full gate passes, including the anonymity gate (`hub/tests/test_anonymity.py`).
3. Scope guard: changed files ⊆ owned two, plus fix-scope `hub/*.py` only if a FINDING commit
   message names them.
4. Free ports, temp `HOME`/`XDG_*` set by the tests, explicit modes; the suite never touches the
   real registry directory (`~/.local/share/{project}/projects`), which `write_projects` already
   avoids.

## Out of scope

No broker or oc file. No re-typing of X1–X24 (`test_a2h_*`) or of the admin-session matrix
(step 6). No product code changes without a FINDING.

## Notes (worker rules)

No git history commands. Host facts: umask 002 — assert modes explicitly; the sandbox has no
docker/systemd, but the hub layer needs neither (the launchers and upstreams are the httputil
fakes). Run long suites detached (`setsid -f`); this module's wall time should stay under ~60 s
like `test_a2h_relay`'s. While working, run only your two modules; the full gate once at the
end. Your verify (from `a2x-chain.json`) is the check the orchestrator trusts; do not substitute
a narrower one.
