# H3w step 1: roles from config, the gate's two-role Host/Origin rules, one routing+caps table

## Goal

Turn the single-origin hub into a **role-aware** one, from config up. `public_hosts`
becomes `sites` (each hostname carries exactly one role). The gate's step 3 resolves the
request's role and its **browser self-origin**; step 5 now requires `Origin` to equal that
self-origin (a sibling public host is refused). Routing and body caps come from **one
table** shared by both roles, so a cap and a route can never drift apart again. On the
OpenCode role the hub relays everything (including `/sw.js`) to OpenCode and appends a
`frame-ancestors` CSP naming its paired hub origin; hub responses get a `frame-src` that
includes the paired OpenCode origins. `/h/_hub/…` is reserved. **Both the new root layout
and the existing `/hub/…` tree are served in this step** so the shipped UI and every
existing test stay green — the `/hub`→308 and the static move are step 2.

Binds: `docs/h3-design.md` §2 (R-H3-1/2/3), §3 (URL space + the two role tables), §4 (the
gate changes, in order), §6.1–6.3 (config), §6.6 (caps), §10.1/10.3. This is the slice's
hard boundary (gate, routing, Origin, caps, framing). `docs/h1-design.md` §2 D3 and §11.1
are **superseded** by this step's config; leave those files untouched (historical).

## Read first

- `docs/h3-design.md` **in full** — §2 rulings, §3 URL space (both role tables verbatim),
  §4 the gate's new order and the self-origin rule, §6.1–6.3 config, §6.6 caps,
  §8 step-0 spike findings (the CSP-override proof), §10 rulings. Not re-decidable.
- `docs/specs/h3w-design.md` §3 — the shared seams this step defines for steps 2–5.
- `docs/h1-design.md` §4 (current gate order, statuses, body caps) and §4.5 (the h1 Origin
  rule this step replaces) — keep every other gate property identical.
- `hub/config.py` (whole): `ALLOWED_HUB_KEYS`, `_public_host_ok`, `HOST_NAME_RE`,
  `PORT_RE`, `DNS_LABEL_RE`, the one-`_check_*`-per-key idiom, `HubConfig`,
  `load_hub_config`'s 0600 pre-read refusal, `ConfigError` naming the key never the value.
- `hub/gate.py` (whole): `_step_host`, `_step_origin`, `body_cap`, the fixed refusal
  bodies, the exact step order, how `_step_host` normalises Host today.
- `hub/proxy.py`: `route_for(target, hosts, root_host)`, `ROOT_SW_PATH`/`ROOT_SW_BODY`.
- `hub/api.py`: `csp_for(origins)`, `_CSP_HEAD`/`_CSP_TAIL`, `NO_STORE_NAMES`, how the
  `/hub` prefix is stripped and served now.
- `hub/__main__.py`: `build_server`, handler verb arming via `__getattr__`, gate→route→
  relay/handler wiring.
- `hub/tests/httputil.py` (`PUBLIC_HOSTS`, `ROOT_HOST`, `write_config`, `HubTestCase`,
  `ProxyTestCase`, `free_port`), `test_origin.py`, `test_host.py`, `test_gate_order.py`,
  `test_routing.py`, `test_request_line.py` — every test the role split touches.
- `docs/specs/h1-1-config-verifier-gate.md` — the house shape of a step spec.

## Contract

### Files

Modify: `hub/config.py`, `hub/gate.py`, `hub/proxy.py`, `hub/api.py`, `hub/__main__.py`,
`hub/tests/httputil.py`, and the existing hub test modules the role split forces
(`test_config.py`, `test_origin.py`, `test_host.py`, `test_gate_order.py`, `test_routing.py`,
`test_request_line.py`, `test_resources.py`, `test_cache.py`, `test_headers.py`,
`test_sessions_ui.py`, `test_h1_acceptance.py`, `test_h2_acceptance.py`, `test_websocket.py`,
`test_streaming.py`, `test_logging.py`, `test_verifier.py`, `test_install.py`,
`test_doctor.py` as needed). Add tests to `test_config.py`, `test_host.py`, `test_origin.py`,
`test_routing.py`; new module `hub/tests/test_roles.py` for the cross-role matrix. Do **not**
touch `hub/static/**`, `install.sh`, `hub/doctor.py`, any `docs/**` other than your own notes,
or `daemon/**`. Python 3.11+ stdlib only (D1 unchanged).

### `hub/config.py`

- `ALLOWED_HUB_KEYS`: drop `public_hosts`, add `sites`; keep the rest.
- `sites`: non-empty list; each entry a JSON object, allowed keys `hub` (required) and
  `opencode` (optional). Each value passes the existing `_public_host_ok` (bare lowercase DNS
  name, no scheme, no port, no trailing dot). One `_check_sites` in the existing per-key idiom.
- **Global uniqueness:** collect every hostname across all entries and both fields; a repeat
  anywhere → `ConfigError` naming the key, not the value ("no host in two roles, no host in two
  sites").
- A parsed doc with `public_hosts` and no `sites` (or both) → `ConfigError` on `public_hosts`
  saying it was replaced by `sites` (no value echoed).
- `HubConfig`: add `sites: tuple[Site, ...]` (`Site` frozen dataclass `hub`, `opencode: str|None`).
  Keep a `public_hosts` **property** returning every hostname (hub then its opencode, config
  order) so existing call sites are unchanged. Add `role_of(host)`, `hub_hosts`, `opencode_hosts`,
  `opencode_for(h)`, `hub_for(h)`; comparison is port-stripped, lowercased.

### `hub/gate.py`

- `_step_host`: after the membership check compute **role** = `config.role_of(name)` and
  **self_origin** = `"https://" + browser_origin_of(host_header)`, where `browser_origin_of`
  lowercases, drops one trailing dot, drops a trailing `:443`, keeps any other port (so the
  browser stack on an ephemeral port matches its own Origin). Statuses unchanged (421 for unknown
  / wrong-role-for-path).
- `body_cap(raw_target, role)` reads the **single table** (below), returns h1 §6.6's caps per
  prefix per role, defaults as today. Fixed refusal bodies byte-identical.
- `_step_origin`: for non-GET/HEAD **and every WS upgrade (GET + `Upgrade: websocket`)** require
  `Origin == self_origin`. Missing / `null` / `http://…` / a different host (incl. a sibling
  public host) → the same 403 body. `Sec-Fetch-Site` unchanged. Origin-less GET/HEAD page loads
  still pass.

### One routing + caps table (`hub/proxy.py` + `hub/gate.py`)

One module-level ordered table; `route_for(target, role, root_host, config)` and
`gate.body_cap(raw_target, role)` both index it, no parallel `if` chain. Rows/statuses exactly
`docs/h3-design.md` §3's two role tables and the `h3w-design.md` §3 table: hub role serves the
root layout **and still serves `/hub/…` unchanged** (308 is step 2); opencode role relays `/sw.js`
and everything else to the root host's OpenCode, routes `/h/<host>/oc(/…)`, reserves
`/h/_hub/…`, 404s any other `/h/…`. `_hub` is unreachable as a host because `HOST_NAME_RE` needs a
leading letter/digit — assert it. Remove `ROOT_SW_PATH`/`ROOT_SW_BODY` and their wiring; on the
opencode role `/sw.js` is relayed untouched.

### Framing (`hub/api.py`)

- `csp_for(origins)` gains the paired OpenCode origins: on a hub response
  `frame-src 'self' <https://paired-opencode per site, config order> <auth origins>`; origins from
  config only, never the request Host.
- On every opencode-role relayed response, append a **second** header
  `Content-Security-Policy: frame-ancestors 'self' https://<paired hub host(s)>` (do not merge
  into an upstream CSP; never add `X-Frame-Options`).

### Tests (row-by-row, both roles)

`test_config.py`: sites accepted; a name used as `hub` in one entry and `opencode` in another
refused; a name in both fields of one entry refused; `public_hosts`-only refused with the fix
message. New `test_roles.py` over a real socket: `GET /api/me` with an **opencode** Host → 421;
`GET /h/<self>/oc/` routes to OpenCode on both roles; POST with a **sibling** origin → 403; POST
with own origin → passes; WS-upgrade GET with **missing**/`null`/sibling Origin → 403, own →
allowed; Host wrong-case / `:443` / ephemeral `:port` (matches own Origin) / trailing dot;
`/hub/…` still served here; on the opencode role `/sw.js` relays (upstream sees `/sw.js`, not a
replacement body) and the response carries the appended `frame-ancestors` with the paired hub
origin; body-cap rows checked per role against the table.

## Acceptance

`python3 tools/run_tests.py` (both suites, full — this is a hard step). Scope guard
`! { git diff --name-only h3w-base; git ls-files --others --exclude-standard; } | grep -vE
'^(docs/specs/h3w-|hub/)'` passes and no `docs/h3-*`/`docs/h1-*`/`h2-*` spec is touched. No UI
change → no screenshots.

## Out of scope

The `/hub`→308, the static/manifest/worker root move, the Chat iframe origin change, the
installer/doctor, the OpenCode-origin renewal, the browser two-hostname stack, and the
end-to-end acceptance — all later steps. Serving only the root layout (dropping `/hub`) is
**step 2**, deliberately, so this step keeps the shipped UI working.

## Notes

The 2026-11-14 413 regression was routing/caps drifting apart; the single table is the
structural fix, so a reviewer should find no `if`/`elif` prefix chain in either `body_cap`
or `route_for` after this — both index the same ordered table.
