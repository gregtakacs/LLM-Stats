# H3 step 1: `sites` config, a role per hostname, Origin = the request's own origin

`"hard": true`: config validation, the gate's Host step and its Origin step. This is the first
half of design step 1 (`docs/h3-design.md` §8). The URL space does **not** change in this step:
routing, body caps, `/hub/` and the static tree stay exactly as they are; step 2 moves them. Every
test module, the browser ones included, must still pass at the end of this step.

## Read first

- `docs/h3-design.md` all of it (binding; §2 rulings, §4 gate, §6 config, §10 rulings).
- `docs/h1-design.md` §3.2 (`hub.json` validation style), §4 (the gate), §10 (test classes).
- `AGENTS.md` (test runner, test policy, free ports).
- `hub/config.py` (`ALLOWED_HUB_KEYS`, `HubConfig`, `_check_public_hosts`, `_public_host_ok`,
  `DNS_LABEL_RE`, `ConfigError` wording style), `hub/gate.py` (all), `hub/doctor.py`
  (`check_verifier`, `check_gate`, `healthcheck`: the three `public_hosts[0]` users),
  `hub/api.py` (`hosts_payload`: the Host is part of the cache key), `hub/install.sh`
  (`--public-host` parsing, `public_host_normalized`, `write_hub_config`, `usage`).
- Tests: `hub/tests/httputil.py` (`write_config`, `PUBLIC_HOSTS`, `HubTestCase`),
  `hub/tests/test_config.py`, `test_host.py`, `test_origin.py`, `test_gate_order.py`,
  `test_install.py`, `test_doctor.py`, `test_h2_acceptance.py` and
  `test_h2_browser.py` (`BrowserStack._start_hub`) — the places that write a `hub.json`.

## Contract

### 1. `hub.json`: `sites` replaces `public_hosts`

```json
"sites": [
  {"hub": "hub.example.com", "opencode": "code.example.com"},
  {"hub": "hub.lan.example.com", "opencode": "code.lan.example.com"},
  {"hub": "hub.other.example.com"}
]
```

- `ALLOWED_HUB_KEYS`: `public_hosts` out, `sites` in. `sites` is **required**.
- A document that has `public_hosts` (with or without `sites`) is refused with exactly:
  `config key 'public_hosts' was replaced by 'sites' (one {"hub": H, "opencode": H} entry per
  site; see docs/hub-install.md)` — this check runs **before** the unknown-key check, so the
  message is this fix line, not "unknown key". No silent single-origin mode, no fallback.
- `sites`: a JSON array, 1 to 16 entries, each a JSON object whose keys are only `hub`
  (required) and `opencode` (optional). Each value is a string accepted by the existing
  `_public_host_ok` (one lowercase DNS name, no port, wildcard, path, underscore, trailing or
  double dot). Every hostname appears **once across all entries and both roles** (a name that
  is one site's `hub` and another's `opencode`, or both roles of one entry, is refused).
- Error messages name the entry index and the key, never the value:
  `invalid hostname at sites[1].opencode`, `duplicate hostname at sites[2].hub`,
  `unknown key at sites[0]`, `sites[3] must be a JSON object`,
  `config key 'sites' must be a JSON array`, `config key 'sites' must not be empty`,
  `config key 'sites' must hold at most 16 entries`, `missing hub at sites[0]`.
- `HubConfig` loses `public_hosts` and gains:
  - `sites: tuple[Site, ...]`, `Site` a frozen dataclass `(hub: str, opencode: str | None)`;
  - `roles: Mapping[str, str]` hostname → `"hub"` or `"opencode"` (read-only mapping);
  - `pair: Mapping[str, str | None]` hostname → its sibling in the same entry (a hub's OpenCode
    hostname or `None`; an OpenCode hostname's hub hostname).
  Remove every use of `public_hosts` in `hub/` (grep: none may remain outside the refusal message
  and its tests).

### 2. Gate step 3 yields the role

`_step_host` normalises exactly as today (strip, lowercase, port stripped, one trailing dot
dropped, bracketed IPv6 handled) and then looks the result up in `roles`: absent → 421 (as
today); present → the request has a `host` and a `role`. `evaluate` keeps both; store them on the
handler as `handler.{project}_host` and `handler.{project}_role` (step 2 of this slice routes on them;
nothing reads them yet except the Origin step).

### 3. Gate step 5: Origin = this request's own origin

For every method other than GET/HEAD and for every request carrying `Upgrade` (as today), the
`Origin` header must be present and **byte-equal** to `"https://" + <the normalised Host of this
request>`; anything else → 403. So `Origin: https://code.example.com` on a request whose Host is
`hub.example.com` is refused even though both are configured (that is the point: same-site
siblings, design §4). The `Sec-Fetch-Site` rule is unchanged (`same-origin` or `none` when
present). Upgrade with no Origin → 403 (unchanged).

### 4. The installer writes `sites`

- `--hub-host H` (repeatable) and `--opencode-host H` (repeatable) replace `--public-host`. The
  i-th `--opencode-host` pairs with the i-th `--hub-host`; more `--opencode-host` than
  `--hub-host` flags → usage error `--opencode-host has no --hub-host to pair with (pairs by
  order)`. Each value is normalised and validated with the existing `public_host_normalized`
  rules; a hostname given twice anywhere (either flag) → usage error `hostname 'H' given twice`.
- `--public-host` (any value) → usage error, exit 2:
  `--public-host was replaced: use --hub-host H (the hub's own address) and --opencode-host H
  (OpenCode's address), paired by order`.
- A first install needs at least one `--hub-host` (the message names `--hub-host`). The written
  `hub.json` has `"sites": [{"hub": …, "opencode": …}, …]` (key `opencode` omitted when unpaired)
  and no `public_hosts`. The summary line says `(600, N site(s))`.
- An existing `hub.json` is still never rewritten in this step (step 5 adds the migration of an
  old one); the usage text lists the two new flags in place of `--public-host`.
- `daemon/tests/test_install_docs.py` checks that the documents' flag tables match the
  installer's parser arms. Keep it green with the **minimum** doc edit: in `docs/hub-install.md`
  replace the `--public-host` row with `--hub-host H` and `--opencode-host H` rows (and one row or
  sentence saying `--public-host` is refused with the fix line), fix the one example command, and
  the same in `docs/hub-agent-install.md`'s flag list and command. Everything else in the docs is
  step 5's; adjust `test_install_docs.py` only if the refusing `--public-host` arm needs a
  documented-as-refused exception, and never by weakening a check.

### 5. Doctor and healthcheck

Wherever `hub.public_hosts[0]` was used, use `hub.sites[0].hub`. Paths stay `/hub/` in this step.

## Tests (required; then look beyond this list for the neighbouring cases)

The harness first: in `httputil.py` replace `PUBLIC_HOSTS` with
`SITES = [{"hub": "hub.example.com", "opencode": "code.example.com"},
{"hub": "hub.local.example.com", "opencode": "code.local.example.com"}]`, export
`HUB_HOST = "hub.example.com"`, `OC_HOST = "code.example.com"` and
`PUBLIC_HOSTS = [every hostname in SITES]` (kept for tests that iterate). `HubTestCase.host`
stays `OC_HOST`; add `HubTestCase.hub_host = HUB_HOST`. Every test that sends an `Origin` sends
the one of the Host it sends. Replace every real domain in `hub/tests/` identities
(`…@{domain}` and similar) with `example.com` names, except the installer's
`FORBIDDEN_ANYWHERE` guard (R-H3-3).

- **Config** (`test_config.py`), each with a passing neighbour: one site with and without
  `opencode`; three sites; `public_hosts` alone, `public_hosts` + `sites`, and `public_hosts: []`
  all give the fix line; `sites` missing, not a list, empty, 17 entries; an entry that is a
  string, a list, `null`; an entry with `hub` missing, an extra key (`"root"`), a non-string
  value; hostnames `HUB.example.com`, `hub.example.com.`, `hub.example.com:443`, `*.example.com`,
  `hub_x.example.com`, `hub..example.com`, `""`; the same name as `hub` of two entries, as `hub`
  of one and `opencode` of another, as both roles of one entry, and differing only in case
  (refused as invalid uppercase, never deduplicated); error messages never contain the value
  (assert a distinctive value is absent from `str(exc)`); `roles`/`pair` contents for a 3-site
  config; `roles` is read-only.
- **Host** (`test_host.py`): every configured hostname of both roles is accepted with case,
  `:port` and one trailing dot variations, and the role recorded is the right one (assert through
  a request the Origin step can tell apart: see below); a foreign Host, `hub.example.com..`,
  `example.com`, `xhub.example.com`, `hub.example.com.evil` → 421 with zero verifier calls.
- **Origin** (`test_origin.py`, rewrite it for two roles): for a POST and for a WebSocket upgrade
  GET, on a hub Host and on an OpenCode Host: own origin passes; the **sibling** origin (the
  other hostname of the same site) → 403; another site's hostname → 403; `Origin: null` → 403;
  missing → 403; `http://` own host → 403; own host with `:443`, with a trailing `/`, with a
  path, with a trailing dot, in uppercase → 403; a request with `Host: HUB.EXAMPLE.COM:8443`
  passes with `Origin: https://hub.example.com` (the normalised Host) and fails with
  `Origin: https://HUB.EXAMPLE.COM:8443`; `Sec-Fetch-Site: same-site` with the own Origin → 403.
  **Control:** the sibling-origin test must fail against `1f19283`'s gate logic (it accepted any
  configured host); say in the report how you checked that (e.g. temporarily reverting
  `_step_origin` locally, never committed).
- **Gate order** (`test_gate_order.py`): still green; any Origin/Host fixtures follow the roles.
- **Installer** (`test_install.py`): first install with one `--hub-host`; with two hub hosts and
  one `--opencode-host` (the second site unpaired); `--public-host` refused with the fix line and
  nothing written; `--opencode-host` with no `--hub-host`; three opencode flags for two hub
  flags; a hostname given as both `--hub-host` and `--opencode-host`; invalid values on each
  flag (`Bad Name`, `x.example:8080`); the written file loads with `load_hub_config` and has no
  `public_hosts`; the existing never-overwritten test keeps its meaning with a `sites` document.
- **Doctor** (`test_doctor.py`) and the other modules that write a `hub.json`: updated fixtures;
  doctor still probes the first site's hub hostname.
- `BrowserStack` in `test_h2_browser.py`: its config becomes `"sites": [{"hub": HOST}]`; the
  browser modules must pass unchanged otherwise.

## Verify

While working: `python3 tools/run_tests.py hub.tests.test_config hub.tests.test_host
hub.tests.test_origin hub.tests.test_gate_order hub.tests.test_install hub.tests.test_doctor
daemon.tests.test_install_docs`.
Once at the end: `python3 tools/run_tests.py` (both suites). The harness re-runs both suites and
requires the three browser modules to report `OK` without skips.

## Out of scope

Routing, body caps, the `/hub` prefix, `/sw.js`, CSP and framing headers, `/api/hosts` contents
(step 2); `hub/static/` (step 3); the installer's migration of an old `hub.json`, doctor's
per-site checks, docs and printed snippets (step 5); `hub/verifier.py`, `hub/proxy.py`,
`hub/wsrelay.py`, `hub/streams.py`; the daemon.
