## Scores (0–2)

| # | Criterion | X | Y |
|---|---|---|---|
| 1 | Rulings fidelity | 0 | 2 |
| 2 | Boundary coverage | 1 | 2 |
| 3 | Hard flags and verifies | 1 | 2 |
| 4 | Step sizing and order | 0 | 1 |
| 5 | Executability | 0 | 2 |
| 6 | Owner questions | 0 | 1 |
| 7 | Errors | 0 | 1 |
| | **Total** | **2** | **11** |

## Evidence

1. **Rulings fidelity.**
   - X contradicts the design in four places:
     - It relays every `/h/<host>/oc/…` path on the hub role (X/plan-design.md:99, X/plan-1:115). The design (h3-design.md:40) says that row is OpenCode's **API** only.
     - It answers `/api/me` on an OpenCode Host with 421 (X/plan-design.md:76, X/plan-1:114, X/plan-5:52). The design (h3:51) relays "everything else" on that origin to OpenCode.
     - The failure link goes to the hub's `/api/login` (X/plan-3:68). The design (h3:99–100) opens the OpenCode origin top-level.
     - It lets the worker keep `--public-host` as an alias (X/plan-4:49–52). §6 (h3:120) says it is refused.
   - Y matches every ruling. It refuses `public_hosts` before the unknown-key check (Y/plan-1:36–39). It relays `/sw.js` (Y/plan-2:52, :106). It removes real domains from test identities too (Y/plan-1:110–112; hub/tests/httputil.py:44 really holds `{owner-email}`).
2. **Boundary coverage.**
   - X states most checks but misses the `/hub//evil.example` open redirect (X/plan-2:69: `Location = /<rest>`). It never says where the cap check goes once caps need the role (gate.py:106 runs `body_cap` before `_step_host` at :109).
   - X's neighbours beyond the brief (about 8): `http://` Origin; an ephemeral `:port` Host; `/h/../` and `%2e%2e`; `/hub/..`; `Sec-Fetch-Site: cross-site`; "no refusal forwards upstream"; `_hub` unreachable via `HOST_NAME_RE`; a third-host Origin.
   - Y's neighbours beyond the brief (40+):
     - Config: 17 entries; entries that are a string, list or null; an extra key; a non-string value; wildcard, underscore and `..` hostnames; case-only duplicates; the value never appears in the error.
     - Host: `xhub.`, `hub.example.com.evil`, `hub.example.com..`.
     - Origin: own host with `:443`, a trailing `/`, a path, uppercase; `Sec-Fetch-Site: same-site`.
     - Routes: `/h/alpha/oc/api` vs `apix`; `/h/_hubx`, `/h/_HUB/`, `/H/`, `/hx`, `/h_`, `/apix`, `/hub.js`, `/HUB/`, `/hub//evil.example`.
     - Caps: cap+1 sent as a header only; exactly cap; the 1 MiB prompt regression; oversize with a foreign Host gives 421.
     - Upgrades: a hub-role upgrade gets 400.
     - Framing header: present on 401/403/413/502, absent on 101 and on pre-Host 421/405.
     - Second-site pairing isolation.
     - `/h/_hub/` variants: `;x`, `%72enew.html`, `//renew.html`.
     - Browser: a forged postMessage, concurrent renewals, `chatOrigin` rejecting `javascript:`, uppercase and a port, a third origin framing either site, sibling CSRF via `no-cors` fetch and a form.
3. **Hard flags and verifies.**
   - X's verify greps never check the browser modules except `test_h2c_browser` in step 3 (X/chain:11, :17, :35). `run_tests.py` prints `OK (skipped=N)` for a skip (tools/run_tests.py:35, :97), so a skipped browser run passes steps 1, 2, 4 and 5.
   - X step 2 is light but adds the 308 redirect boundary, and its verify omits `test_sessions_ui` and `test_h2c_browser`, both of which it edits.
   - X's scope regexes are `^(hub/|…)`, too wide to catch drift.
   - Y: every boundary step is hard (1, 2, 4, 6), each verify greps the browser modules for `OK$`, and each scope guard is file-level against the previous step's branch (Y/chain:11–41).
4. **Step sizing and order.**
   - X step 1 is all of design step 1 (config, gate, single table, framing, fixtures across about 20 test modules), so it is oversized.
   - X's claim that step 1 keeps the shipped UI working is false (see defect X-2).
   - Y orders routes before the UI and adds the two-hostname front in step 3, the first step that needs it. Steps 2 and 3 are borderline on size.
5. **Executability.**
   - X invents `/api/login`; grep finds no login route in hub/api.py or hub/static.
   - X step 1's file list omits `test_h2_browser.py`, whose `_start_hub` writes `public_hosts` (test_h2_browser.py:316). It also forbids `install.sh`, but `test_install` loads the installer's output with `load_hub_config` (test_install.py:350).
   - Every name Y uses exists: `_check_public_hosts`, `public_host_normalized`, `write_hub_config` (install.sh:800), `check_opencode_entry`, `format_line`, `OriginDevTools`, `watch_origin`, `_iframeRenew`, `chatSrcFor`, `RETURN_AFTER_MS`, `FORBIDDEN_ANYWHERE`, `log_fields`, `_is_daemon_route`.
   - Both chain JSONs parse.
6. **Owner questions.** Neither plan lists any.
   - X hands real decisions to the worker: alias or refuse `--public-host`, and where the sign-in link lives (X/plan-3:44–48, :99–104).
   - Y re-asks nothing settled and records its own narrowing of the hub's `/h/<host>/oc` row to `/oc/api…` (Y/plan-2:54–56). Neither raises how a cross-origin OpenCode iframe would "report signed-out" (h3:96–97).

## Defects, ranked by severity

**X**
1. **Security hole.** The hub role relays all of `/h/<host>/oc/…`, so OpenCode's HTML (which shows agent-written content) runs on the hub origin with the hub's cookies. That defeats §4's same-site split.
2. **Step 1 cannot pass.** Its hub-role catch-all 404 breaks today's picker (`apiBase` returns `""`, so it calls `/api/session` same-origin; sessions.js:73–79) and the same-origin Chat iframe. Its own full-suite verify then fails, because `hub/static` is out of scope. `test_install` also fails, because `install.sh` is frozen while the config now refuses `public_hosts`.
3. **Open redirect.** `/hub//evil.example` answers 308 with `Location: //evil.example`.
4. **Step 3's renewal is broken.**
   - It is framed by "OpenCode's own top-level page", which needs OpenCode to be modified (against R-H3-2).
   - It posts to `location.origin`, which is the OpenCode origin, so the hub parent would never receive the message.
   - Its failure link targets the nonexistent `/api/login`.
5. `/api/me` on the OpenCode host gives 421. Taken as a rule for `/api/…` on that origin, it breaks OpenCode's own `/api/session`.
6. Its migration turns every old `public_hosts` entry into a `hub` entry, so a `{opencode-host}` host would get the hub role. It also leaves `--public-host` alias-or-refuse to the worker.
7. Skipped browser runs pass most verifies, the step 2 verify skips the modules it edits, and the scope guards are too wide.
8. `body_cap(raw_target, role)` is specified, but nothing moves the cap check behind the Host step.

**Y**
1. Step 2 deliberately leaves the shipped UI and the three browser modules red until step 3 (Y/plan-2:5–8). The chain passes, but the branch between those steps is broken.
2. Origin is compared with the port-stripped Host, so `Host: hub.example.com:8443` accepts `Origin: https://hub.example.com`. That is slightly looser than "own origin"; it doesn't matter behind a reverse proxy on 443.
3. Steps 2 and 3 are large: step 2 rewrites the URL space in every non-browser module, and step 3 builds a DevTools front with a reader thread and ports three browser modules to it. Either could overrun.
4. The service worker is never exercised in a browser (Y/plan-3:94); it is tested only statically.

## Worth borrowing

- **X from Y:** the API-only `/h/<host>/oc/api` row, with the hub CSP added on relayed responses; the open-redirect guard; the cap check after the Host step; moving the installer into step 1; the postMessage renewal design checking `event.source`, `event.origin` and `event.data`; the browser-module `OK$` greps; the R-H3-2 control asserting the exact set of headers allowed to differ.
- **Y from X:** a shared-seams design note for the whole slice (X/plan-design.md §3); keeping a non-443 port in the self-origin; the `/h/../` and `%2e%2e` traversal cases and `Sec-Fetch-Site: cross-site`; the explicit "NOT VERIFIED, never add a skip" rule (X/plan-5:84–86).

## Verdict

X cannot run as-is. Step 1's full-suite verify fails because the shipped picker and chat lose their same-origin OpenCode routes and the installer still writes `public_hosts`, both in files the spec forbids touching. If a worker forced it through, it would ship OpenCode pages on the hub origin, a `/hub//` open redirect and a renewal that can never succeed. Y could run essentially as-is. Each verify enforces non-skipped browser runs and tight scope, the names it cites exist, and its routes match the design. Its real costs are a deliberately red UI between steps 2 and 3 and two steps that may overrun the size budget; splitting step 3, with the front first and the UI paths second, would remove the main risk.
