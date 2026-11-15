# H3 step 2: one route table per role — routing, body caps, `/hub` 308, `/sw.js`, framing headers

`"hard": true`: routing, body caps, framing headers, the hub's CSP. Second half of design step 1
(`docs/h3-design.md` §3, §4). Step 1 gave every request a `{project}_host` and a `{project}_role`;
this step makes the URL space depend on the role. `hub/static/` is **not** touched (step 3 moves
the UI's own paths), so the three browser modules (`test_h2_browser`, `test_h2c_browser`,
`test_sessions_ui`) are expected to fail after this step and are excluded from its verify; do not
edit them. Every other module must pass.

## Read first

- `docs/h3-design.md` §3, §4, §7 (binding); `docs/h1-design.md` §4, §6.1, §6.3, §6.5, §6.6,
  §6.7, §8.1, §8.3; `docs/h2-design.md` §5.6 (the CSP key).
- `hub/gate.py` (`_step_framing`, `body_cap`, `_is_daemon_route`, `Decision`, `respond`),
  `hub/proxy.py` (`Route`, `route_for`, `_forward_target`, `strip_auth_token`, `log_fields`,
  `log_access`, `serve`, `ROOT_SW_*`, `_serve_root_sw`, `relay_response_headers`, `_relay`),
  `hub/api.py` (all), `hub/__main__.py` (`_run_gate`, `build_server`, `main`), `hub/wsrelay.py`
  (how the 101 and the relay are written), `hub/doctor.py` (`check_gate`, `healthcheck`).
- Tests: `hub/tests/httputil.py`, `test_routing.py`, `test_headers.py`, `test_gate_order.py`,
  `test_logging.py`, `test_ui.py` (its server-side classes only), `test_h1_acceptance.py`,
  `test_h2_acceptance.py`.

## Contract

### 1. The table (new module `hub/routes.py`, the only place routes and caps are decided)

`classify(role, raw_target, host_names, root_host) -> Route`, a frozen dataclass with `row`
(the id below), `kind`, `host_name` (or `None`), `cap` (bytes), `target` (what to forward, or the
`Location` for a redirect, else the raw target) and `log_class`. Matching is on the **raw,
undecoded** path (the part before `?`), case-sensitive, segment by segment; `<known>` is a
segment that matches `HOST_NAME_RE` **and** names a `hosts.json` entry. `CAP_HUB = 64 KiB`,
`CAP_DAEMON = 0`, `CAP_OPENCODE = 32 MiB` (today's values) live here.

**Hub role**

| Row | Path | kind | cap | forward / answer |
|---|---|---|---|---|
| H1 | `/hub` or `/hub/…` | `redirect` | 64 KiB | 308, see §3 |
| H2 | `/api` or `/api/…` | `hub-api` | 64 KiB | `/api/me`, `/api/hosts` (today's handlers), any other → 404 |
| H3 | `/h/<known>/api` or `/h/<known>/api/…` | `daemon` | 0 | that daemon, target `/` + rest (today's daemon rule, GET/HEAD only) |
| H4 | `/h/<known>/oc/api` or `/h/<known>/oc/api/…` | `opencode` | 32 MiB | that host's OpenCode, target `/api…`, `auth_token` stripped |
| H5 | any other `/h` or `/h/…` | `not-found` | 64 KiB | 404 |
| H6 | everything else | `static` | 64 KiB | `/` and `/index.html` → `index.html`; else a file under `hub/static/` (today's `_static` containment) or 404; a path starting with `//` → 404 |

**OpenCode role**

| Row | Path | kind | cap | forward / answer |
|---|---|---|---|---|
| O1 | `/h/_hub` or `/h/_hub/…` | `reserved` | 64 KiB | 404 in this step (step 4 serves two files here) |
| O2 | `/h/<known>/oc` or `/h/<known>/oc/…` | `opencode` | 32 MiB | that host's OpenCode, target `/` + rest, `auth_token` stripped (today's rule) |
| O3 | any other `/h` or `/h/…` | `not-found` | 64 KiB | 404 |
| O4 | everything else, **`/sw.js` included** | `opencode` | 32 MiB | the root host's OpenCode, target unchanged except `auth_token` stripped (today's rule) |

H4 is deliberately narrower than the design's "`/h/<host>/oc/<rest>`": the hub origin relays only
OpenCode's **API** (the picker's sessions calls); OpenCode's pages never render on the hub
origin. `/h/<known>/oc`, `/h/<known>/oc/` and `/h/<known>/oc/apix` on the hub role are H5.

`log_class`/host for the §6.7 access line: daemon rows `api <name>`, OpenCode rows `oc <name>`
(O4: the root host), every other row `hub -`. A request refused before the Host step has no role:
its line says `- -`.

### 2. The gate

- Step 2 keeps the `Transfer-Encoding` (501) and `Content-Length` shape (400) checks. The cap
  comparison moves to **right after step 3**: with the role known, `route = classify(...)`; a
  `Content-Length` above `route.cap` → 413, before identity (the verifier is never called for a
  413). So an oversize body with a foreign Host is now 421, not 413.
- `gate.body_cap` and `gate._is_daemon_route` are deleted; no other copy of the table may exist.
  `Decision` gains `route` (the `Route` for `action="route"`); the handler keeps it as
  `handler.{project}_route`. `_run_gate` dispatches on `route.kind` (`daemon`/`opencode` → the
  proxy; every other kind → `api.serve`); `proxy.serve` uses that route and never recomputes it.
  `proxy.route_for` and `proxy.log_fields` are deleted.
- **Upgrades** (`Upgrade: websocket`): relayed only on O2 and O4. `not-found` rows answer 404
  first; every other row answers 400 with no upstream contact (H4 included: the picker uses no
  socket).
- Methods: H2 and H6 accept GET/HEAD only (405 otherwise, as today); H3 GET/HEAD only (as today);
  H1 redirects every method; `not-found`/`reserved` answer 404 to every method.

### 3. `/hub` → 308 (H1)

`/hub` → `Location: /`; `/hub/<rest>` → `Location: /<rest>`; the query (`?` and everything after
it) appended byte-for-byte. If the resulting location starts with `//`, or contains any byte
outside printable ASCII `0x21–0x7E`, answer 404 instead (never an open redirect: `/hub//evil.example`
must not yield `Location: //evil.example`). Body empty, `Content-Length: 0`, `Cache-Control:
no-store`, `Connection: close`, the hub CSP. Only the literal prefix: `/hubx`, `/HUB/`,
`/%68ub/`, `//hub/` are H6 (404 from the static lookup), never redirects. The gate has already run
in full (a cookie-less `/hub/` is a 401, not a 308).

### 4. Headers

- **Hub CSP per hub hostname** (computed once at startup, `server.hub_csp_by_host`):
  `frame-src 'self'` gains `https://<paired OpenCode hostname>` (when the site has one) and then
  the `auth_frame_origins` in config order; no other directive changes. A hub hostname with no
  pairing and no auth origins gets a value byte-identical to `api.CSP`. `api._send` uses the CSP
  of the request's hub hostname on every response it writes (shell, static, API, 404, 405, 308).
- **Relayed responses on the hub role** (H3, H4) additionally get that host's hub CSP as one more
  `Content-Security-Policy` header (the upstream's own CSP headers are kept as they are): an
  OpenCode or daemon answer is never a document that can run script on the hub origin.
- **Every response on the OpenCode role** that the hub writes — relayed (O2, O4, `/sw.js`
  included), the proxy's own refusals (404, 400, 413, 502, …) and the gate's refusals after the
  Host step (401 HTML and JSON, 403, 413, 503) — gets one added header
  `Content-Security-Policy: frame-ancestors 'self' https://<paired hub hostname>` (precomputed per
  OpenCode hostname). OpenCode's own `Content-Security-Policy` and `X-Frame-Options` headers are
  relayed unchanged beside it, never edited, merged or dropped. Not on a 101 response. No other
  response gets it.
- `/sw.js` on the OpenCode role is relayed like any O4 path: delete `ROOT_SW_PATH`,
  `ROOT_SW_BODY`, `_serve_root_sw` and their docstrings' claims.

### 5. `/api/hosts`

Each row gains `"opencode_origin"`: `"https://" + <paired OpenCode hostname of the request's hub
hostname>`, or `null` when that site has none; `"oc_url"` becomes
`opencode_origin + "/h/" + name + "/oc"` for every row (root included), or `null` when unpaired.
Nothing else in the row changes; the cache stays keyed by the request's normalised Host.

### 6. Doctor and healthcheck

The cookie-less probes target `/` (not `/hub/`) on the first site's hub hostname; messages say
`GET /`.

## Tests (required; then look beyond this list for the neighbouring cases)

Update every non-browser module to the new space: hub pages and `/api/…` and daemon routes are
asked on `self.hub_host` (`hub.example.com`), OpenCode routes on `self.host`
(`code.example.com`), paths lose `/hub`. Then a new module `hub/tests/test_two_origins.py`:

- **Unit, the table:** `classify` for every row of both roles with its `kind`, `cap`, `target`,
  `log_class`, and the boundaries between rows: `/h/alpha/oc/api` vs `/h/alpha/oc/apix` vs
  `/h/alpha/oc/` on the hub role; `/h/_hub`, `/h/_hub/x`, `/h/_hubx`, `/h/_HUB/` on both roles;
  `/h`, `/h/`, `/h/unknown/oc/`, `/h/ALPHA/oc/`, `/H/alpha/api`, `/hx`, `/h_` on both roles;
  `/api`, `/apix`, `/api/` on both roles; `/sw.js`, `/`, `/index.html`, `/renew.html`, `/hub/`
  on both roles.
- **Caps, row by row on both roles, over HTTP:** `Content-Length` = cap + 1 (header only, no
  body) → 413 with zero verifier calls, for every row; = cap with a real body → not 413 for the
  64 KiB and 0 rows; a 1 MiB POST to O4 `/api/session/x/prompt` and to H4
  `/h/beta/oc/api/session/x/prompt` reaches the fake OpenCode intact (the 2026-11-14 413 class);
  a 65 KiB POST to H2 `/api/me` is 413; a 1-byte body to H3 is 413; oversize + foreign Host → 421.
- **Wrong-role paths:** `/h/alpha/api/status` on the OpenCode role → 404 and the fake daemon saw
  nothing; `/h/alpha/oc/` and `/h/alpha/oc/session` on the hub role → 404 and no OpenCode call;
  `/api/me`, `/api/hosts` on the OpenCode role → relayed to the root OpenCode (its answer, not the
  hub's); `/`, `/index.html`, `/renew.html`, `/sw.js`, `/app.js` on the OpenCode role → relayed;
  `/h/_hub/renew.html` on the hub role → 404; `/hub/` on the OpenCode role → relayed as `/hub/`.
- **`/hub` prefix tricks (H1):** each of `/hub`, `/hub/`, `/hub/app.js?v=1`, `/hub?x=1`,
  `/hub/api/me` → 308 with the exact `Location`; `/hubx`, `/hub.js`, `/HUB/`, `/%68ub/`,
  `//hub/`, `/hub//evil.example`, `/hub//evil.example?x` → 404 and never a `Location` header; a
  cookie-less `/hub/` → 401; `POST /hub/api/me` with the own Origin → 308.
- **`/sw.js`:** on the OpenCode role the fake OpenCode receives `GET /sw.js` and the client gets
  its exact body and `Content-Type`; on the hub role the body is `hub/static/sw.js` byte-for-byte
  and the fake OpenCode saw nothing.
- **Upgrades:** relayed on `/` and `/h/beta/oc/ws` (OpenCode role); 400 with no upstream contact
  on hub-role `/h/alpha/oc/api/event`, `/h/alpha/api/x`, `/`, `/api/me`, `/hub/`; 404 on
  `/h/nope/oc/` (either role) and on `/h/_hub/x`.
- **Framing headers:** on the OpenCode role, a relayed 200 whose fake upstream sends
  `Content-Security-Policy: default-src 'self'` and `X-Frame-Options: SAMEORIGIN` arrives with
  both of those unchanged **plus** `frame-ancestors 'self' https://hub.example.com` as its own
  header; the same added header on `code.local.example.com` names `https://hub.local.example.com`;
  present on a 404 (`/h/nope/`), a cookie-less 401 (HTML and JSON), a 403 (bad Origin), a 413, a
  502 (upstream down), a relayed `/sw.js`; absent on a 101, on every hub-role response, and on a
  pre-Host refusal (421, 405).
- **Hub CSP:** on `hub.example.com` shell, a static asset, `/api/me`, a 404, a 405, a 308: frame-src
  is exactly `'self' https://code.example.com`; with `auth_frame_origins` configured it is
  `'self' https://code.example.com https://auth.example.com`; an unpaired hub hostname (a third
  site with no `opencode`) gets exactly `api.CSP`; a relayed H3/H4 response carries the hub CSP
  in addition to the upstream's.
- **`/api/hosts`:** `opencode_origin` and `oc_url` for `hub.example.com`, for
  `hub.local.example.com` (its own pairing, not the first site's) and `null` for an unpaired hub
  hostname; the root row's `oc_url` is `https://code.example.com/h/alpha/oc`.
- **Host variants route by role:** `HUB.Example.COM:8080`, `hub.example.com.`,
  `CODE.example.com.` reach the right role.
- **Logging:** the class/host per row and `- -` for a 421.
- **Controls (report them):** at least these must fail against `1f19283`'s routing: the
  daemon-on-OpenCode-role 404, the `/sw.js` relay, the hub-role upgrade 400, and the
  `/hub//evil.example` 404 (on `1f19283` `/hub//…` reached the hub's own space). State in the
  report how you checked each.

## Verify

While working: `python3 tools/run_tests.py hub.tests.test_two_origins hub.tests.test_routing
hub.tests.test_headers hub.tests.test_gate_order hub.tests.test_logging hub.tests.test_ui`.
Once at the end: both suites without the three browser modules:
`python3 tools/run_tests.py daemon $(ls hub/tests/test_*.py | sed 's#/#.#g; s#[.]py$##' | grep -vE 'test_(h2_browser|h2c_browser|sessions_ui)$')`.

## Out of scope

`hub/static/` and the three browser modules (step 3); `/h/_hub/` contents and any renewal
(step 4); installer, doctor's per-site checks, docs (step 5); `hub/verifier.py`,
`hub/config.py` (beyond what a route needs to read), the daemon.
