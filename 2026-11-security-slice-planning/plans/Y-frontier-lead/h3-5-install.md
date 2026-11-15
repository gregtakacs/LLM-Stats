# H3 step 5: installer migration, doctor per site, printed snippets, the two documents

`"hard": false`. Design step 4 (`docs/h3-design.md` §6, §9, R-H3-2, R-H3-3). Step 1 already made
the installer write `sites` for a new install; this step migrates an old `hub.json`, gives doctor
one check per site, prints the two-origin reverse-proxy snippets, and rewrites the documents for
the two-origin shape. No change to the gate, the routes or the UI.

## Read first

- `docs/h3-design.md` all (binding); `docs/h1-design.md` §9 (installer, doctor, documents);
  `docs/h2-design.md` §5.6 (auth frame origins), §6.
- `hub/install.sh` (flag parsing, `write_hub_config`, the printed snippets and their order),
  `hub/doctor.py` (`run_checks`, `CHECK_ORDER`, `check_gate`, `check_opencode_entry`,
  `format_line`), `hub/routes.py` (the table the documents describe), `hub/api.py`
  (`/api/hosts` fields), `docs/hub-install.md`, `docs/hub-agent-install.md`, `README.md` (hub
  lines only).
- Tests: `hub/tests/test_install.py`, `hub/tests/test_doctor.py`,
  `daemon/tests/test_install_docs.py` (the flag and doctor-check tables are tested).

## Contract

### 1. Installer: migrating an old `hub.json`

- An existing `hub.json` that is a JSON object with `public_hosts` and no `sites`:
  - with at least one `--hub-host`: rewrite **only that key**: drop `public_hosts`, add `sites`
    built from the flags exactly as a first install builds it, keep every other key and value
    (load, edit, dump; key order kept, `sites` where `public_hosts` was). Atomic replace, mode
    600. Then the file must load with `load_hub_config`; if it does not, put the original bytes
    back and fail (exit 1) naming the problem. Print
    `migrated: hub.json public_hosts -> sites (N site(s))`. Other flags that would change an
    existing file are still not applied (today's "kept existing config" note for them).
  - without `--hub-host`: exit 2, nothing written, with
    `hub.json uses the old 'public_hosts' key: re-run with --hub-host H [--opencode-host H] (repeatable, paired by order) to rewrite it to 'sites'`.
- A `hub.json` that already has `sites` is never rewritten (today's rule), flags or not.
- Anything else that fails to parse: today's behaviour.

### 2. Doctor: one line per site

New check name `site <hub hostname>`, one per `sites` entry, after `gate`. It probes the running
hub (`127.0.0.1:<listen port>`, as `check_gate` does) without a cookie, so it proves what can be
proved without signing in:
- cookie-less `GET /` with `Host: <hub>` → 401;
- when paired: cookie-less `GET /` and `GET /api/session?limit=1` with `Host: <opencode>` →
  401 each, and each carries `Content-Security-Policy: frame-ancestors 'self' https://<hub>`
  (the pairing's framing header);
- the root host's OpenCode answers `/api/session?limit=1` with the hub's credential (reuse the
  `opencode <root>` check's result, do not probe twice).
`OK site hub.example.com: hub 401, code.example.com 401 + frame-ancestors hub.example.com` /
`OK site hub.other.example.com: hub 401, no OpenCode paired`. FAIL lines name the probe and the
status seen, with a fix (rebuild/restart the container; check `sites`). Add the check name to
`CHECK_ORDER` and to the documents' doctor table.

### 3. Printed snippets (replace the single Traefik template, item 1 of the manual edits)

Filled with the first site's hostnames (placeholders `<hub host>`, `<opencode host>` when the
config has none to offer); never a secret, never a site-specific network, address or provider
value. In this order:
1. **Traefik** (one example): two routers to the one `{project}` service — one per hostname role,
   both with `<your auth middleware chain>`, **no** credential/header-injecting middleware on
   either — and the service as today.
2. **Caddy**: one site block for both hostnames with `forward_auth <your login service>` and
   `reverse_proxy {project}-hub:8080` (Host kept).
3. **nginx**: one `server` for both hostnames with `auth_request` to `<your login service>`,
   `proxy_pass http://{project}-hub:8080`, `proxy_set_header Host $host`, HTTP/1.1 and the
   `Upgrade`/`Connection` headers for WebSockets.
4. **Without the hub** (the switch, R-H3-2): the OpenCode hostname's router pointing straight at
   OpenCode (`<opencode url>`) with the proxy's own login **and** a header-injecting middleware
   `Authorization: Basic <base64 of opencode:password>` (a placeholder, never computed or read
   from a secret), plus one sentence: switching back and forth is this router's service line
   only; OpenCode and `hub.json` stay as they are.
The existing site-specific extra edits (the second-network pin and firewall lines) are out of
scope and stay as they are.

### 4. Documents

`docs/hub-install.md` and `docs/hub-agent-install.md`, generic (R-H3-3: `hub.example.com` /
`code.example.com` / `you@example.com`; no real domain, no personal identity; the existing
second-network text may stay but must not be the first thing a reader sees):
- the two-origin shape first: the hub at the root of the hub hostname, OpenCode at the root of
  the OpenCode hostname, what each path does (a short version of the route table: hub origin
  `/`, `/api/…`, `/h/<host>/api/…`, `/h/<host>/oc/api/…`, `/hub…` → 308; OpenCode origin
  everything is OpenCode, `/h/<host>/oc/…` other hosts, `/h/_hub/` the renewal page);
- `sites` in `hub.json`, the two flags, the migration from `public_hosts` (§1);
- the provider cookie-scope note: one cookie for the parent domain, or one per host; with
  per-host cookies the hub renews the OpenCode hostname silently (frame + provider round trip),
  needs the provider origin in `--auth-frame-origin`, and falls back to "Sign in to OpenCode";
- with or without the hub: the switch (snippet 4) and that OpenCode's extra-server list lives on
  the OpenCode origin (re-add servers there after a move: `https://<opencode host>/h/<host>/oc`);
- doctor's new `site` lines in the doctor table; the agent document says to **ask** for both
  hostnames per site.

## Tests (required; then look beyond this list for the neighbouring cases)

- **Installer** (`test_install.py`): migration of an old file with one and with two
  `--hub-host` (one paired, one not): only `public_hosts` → `sites` changed (compare the other
  keys and values to the original), mode 600, it loads, the message line; old file without
  `--hub-host` → exit 2, bytes unchanged, the fix line; old file + a bad `--hub-host` value →
  exit 2, unchanged; an old file that also has an unknown key → restored and exit 1; a `sites`
  file + `--hub-host other.example.com` → unchanged; a symlinked `hub.json` → today's refusal;
  the printed snippets: two Traefik routers naming both hostnames, Caddy and nginx blocks
  naming both, the without-the-hub variant with the `<base64 of opencode:password>` placeholder,
  no credential middleware in the with-hub variants, no secret value and none of the
  `FORBIDDEN_ANYWHERE` literals anywhere in the output.
- **Doctor** (`test_doctor.py`, against an in-process hub as the existing gate checks do): a
  paired site OK; an unpaired site OK with its wording; the OpenCode host answering without the
  framing header (a stub) → FAIL; the hub host answering 200 cookie-less → FAIL; hub down →
  FAIL with the fix; two sites → two lines in config order.
- **Documents** (`daemon/tests/test_install_docs.py`): the flag table and the doctor table stay
  exact; neither document contains a literal of `hub/tests/test_install.py`'s
  `FORBIDDEN_ANYWHERE` (import or mirror that one list; add no new real names to the repo) or
  `public_hosts` outside the migration section.

## Verify

`python3 tools/run_tests.py hub.tests.test_install hub.tests.test_doctor
daemon.tests.test_install_docs` (while working and at the end; the harness runs the same).

## Out of scope

The gate, routes, API, UI and their tests; the default `--network` value and the second-network
pin/firewall printing (O1's generic-deployment work); deploying, restarting or editing anything
live; {infra-repo}.
