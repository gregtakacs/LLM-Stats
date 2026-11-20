# a2x-2 — hub relay hostile suite (in-process)

## Goal

Write `hub/tests/test_a2x_relay_hostile.py` covering design §6's cases AX-R1..R13: the full relay
pair (real gate decision chain + real `hub.proxy.Proxy`) driven over a real socket against a
recording fake container upstream, so every hostile request line, encoding and claim is answered
the way the gate/proxy contract documents — or dialed exactly as documented and nothing more.

## Read first

`docs/specs/a2x-design.md` §6, §9, §11; `hub/tests/test_a2h_relay.py` (the harness to reuse: fake
upstream, cookie builders, the X-row idiom); `hub/gate.py:49-53` (fixed bodies), `:266-302`
(`_raw_target`, `_step_request_line` — the `%2e`-anywhere and `%2f`-host-segment rules),
`_step_origin`, `_step_identity`; `hub/routes.py:198-205` (`_project_api` byte-for-byte matcher and
its docstring's enumeration of fall-through forms); `hub/proxy.py:168-179` (project error bodies),
`:261-266` (audit host slot), `:373-376` (`upstream_for` — password rides its own object);
`docs/specs/a2h-design.md` §4.1, §5.1, §5.3, §10 rows X1..X25; `docs/specs/a2h-2-routes-relay.md`.

## Files owned

- `hub/tests/test_a2x_relay_hostile.py` (new)
- (fix allowlist, only if a case fails: `hub/gate.py`, `hub/proxy.py`, `hub/routes.py` — the fix
  named in a commit-message-ready sentence here before it is made)

## Contract

- Harness: two configured projects `alpha`/`bravo` with distinct upstreams (distinct ports, free
  via `bind(("127.0.0.1", 0))`), the gate in test mode per the existing relay test, sessions signed
  for the right project; one recording upstream per project answering 200 with a body echoing its
  own name, so any cross-dial is visible by construction.
- Per-case expectations exactly as design §6's table: fixed bodies (`BODY_400/401/403/404` —
  `{"error": "…"}` + newline) for refusals; `body_project_offline` + 502 only for AX-R9's
  admin-while-down case; **no other bytes on the wire** (compare `resp.read()` full equality, not
  prefix).
- The audit side is asserted where the case cites it: parse the hub audit JSONL, find the line,
  assert its `host` slot is `p/<name>` and that the *session value* and the client's claims appear
  nowhere in the file (anonymity rule, `hub/tests/test_anonymity.py` scans the new test file too —
  keep literals generic).
- AX-R8: the WS upgrade asserts the *recording* upstream received the `Upgrade` headers once, with
  the password header the upstream object supplied, and no project's password in the audit line.
- Dual-mode run per design §9 (umask 002/XDG-set vs cleared): the relay itself is environment-
  agnostic, so the second mode runs the same sweep as a cheap guard against umask-shaped file
  modes on the state files the harness creates.
- One test method per AX id; docstring cites the design row plus the gate/routes line; no sleep
  longer than 50 ms anywhere.

## Behaviour and edge cases

The list of request lines to sweep is design §6 verbatim; add for each refusal the "nothing dialed"
assertion (both upstreams' recorded counts unchanged). AX-R13's oversize-cookie variants must
distinguish the gate's framing refusals (request too big → which fixed body? cite what the code
does today; a finding that the answer is a *hang* or a raw connection reset is a component bug to
fix in `gate.py` under the allowlist).

## Acceptance criteria

- `python3 tools/run_tests.py` fully green; `ok hub.tests.test_a2x_relay_hostile` present;
  `ok hub.tests.test_anonymity` still green with the new file scanned.
- Scope guard clean (only owned files; component files only if a case forced a fix, stated above).

## Out of scope

The broker (a2x-1), the planner (a2x-3), anything container-side; no changes under `hub/static` or
`launcher/`; the WS *payload* protocol (a2h steps own it — this case proves routing only).

## Notes

The 502-vs-404 distinction in AX-R9 is the suite's guard against a future "always 404" convenience
change: document it in the module docstring.
