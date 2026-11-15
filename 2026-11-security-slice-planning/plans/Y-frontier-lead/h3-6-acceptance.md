# H3 step 6: acceptance — both origins end to end, and OpenCode with or without the hub

`"hard": true`, the last step. Design step 5 (`docs/h3-design.md` §8). Tests only: if a test
finds a defect in `hub/`, stop and report it as a blocker with the failing input (do not fix
product code in this step; the scope guard allows `hub/tests/` only).

## Read first

- `docs/h3-design.md` all (binding: R-H3-1..3, §3 tables, §4, §5, §10).
- `docs/h1-design.md` §6.2 and §6.3 (the request and response header rules: the only allowed
  differences between "through the hub" and "straight to OpenCode").
- `hub/routes.py`, `hub/gate.py`, `hub/proxy.py` (`relay_response_headers`,
  `request_headers_for`), `hub/api.py`.
- `hub/tests/httputil.py`, `hub/tests/test_two_origins.py`, `hub/tests/browser_front.py`,
  `hub/tests/test_h2_browser.py`, `hub/tests/test_h3_renew_browser.py`,
  `hub/tests/test_sessions_ui.py` (its fake OpenCode), `hub/tests/test_h2_acceptance.py` (style).

## Tests (required; then look beyond this list for the neighbouring cases)

### A. `hub/tests/test_h3_acceptance.py` (HTTP, through a real `python3 -m hub serve` subprocess on a free port)

1. **Every row of both §3 tables**, one request each with a valid cookie: the status, which
   upstream (if any) saw the request and with what target, and the cap (cap + 1 → 413, zero
   verifier calls). Driven from one list in the test that names the design row it covers.
2. **R-H3-2, the direct control.** A fake OpenCode that serves `/` (HTML with its own
   `Content-Security-Policy: default-src 'self'` and `X-Frame-Options: SAMEORIGIN`, as a proxy
   in front of OpenCode adds), `/sw.js`, `/assets/app.js`, `/api/session?limit=1` (JSON), a
   `POST /api/session` echo, an SSE `/api/event` (two events, then held open briefly), and a
   WebSocket echo at `/pty/x`. For each: ask it **through the hub** on `code.example.com` and
   **directly**; the status, body bytes (SSE: the two events; WS: the echoed frame) and every
   response header must match, except exactly the documented set: the hub's added
   `frame-ancestors` header; `Set-Cookie` and `WWW-Authenticate` dropped; hop-by-hop and framing
   headers (`Connection`, `Keep-Alive`, `Transfer-Encoding`, `Content-Length` vs chunked);
   `Date`/`Server`. Name the set in one constant, and assert that set is **all** that differs.
   On the request side, what the fake received through the hub differs from the direct request
   only by h1 §6.2's rules (the hub's `Authorization: Basic …`, `X-Forwarded-*`, the identity and
   cookie headers removed): assert the method, target, body and the remaining headers are equal.
3. **Sibling origins:** a `POST` and a WebSocket upgrade on each hostname with the other
   hostname's Origin, with another site's, with `null`, with none → 403, and no upstream saw
   anything; the same request with its own Origin passes.
4. **Two sites:** `hub.local.example.com`'s CSP, `/api/hosts` and framing header name
   `code.local.example.com`, never the first site's hostnames, and vice versa.
5. **Old URLs:** `/hub/`, `/hub/index.html`, `/hub/api/hosts?x=1` → 308 to the root forms.

### B. `hub/tests/test_h3_browser.py` (the front, a fresh profile per scenario)

1. **The whole flow, per-host cookies** (jar: hub only; the fake provider of
   `test_h3_renew_browser.py` reused, session on): open `https://hub.example.com/`; Projects
   populate; choose a project; the picker lists the fake OpenCode's sessions (asked on the hub
   origin as `/h/alpha/oc/api/session`); choose one; the chat child frame's URL is
   `https://code.example.com/server/<key>/session/<id>` and the frame **rendered** the fake's
   page (read its text through `Page.createIsolatedWorld` on the child `frameId` and
   `Runtime.evaluate` in that context) although the fake sends `X-Frame-Options: SAMEORIGIN`.
2. **With and without the hub:** load `https://code.example.com/` twice in fresh profiles: once
   the front routes `code.example.com` to the hub, once straight to the fake OpenCode (the front
   adding the `Authorization: Basic` header a proxy would inject). The document text, title,
   `location.origin` and the list of same-origin request URLs the page made are equal.
3. **Sibling CSRF from agent-written content:** a page the fake OpenCode serves on
   `https://code.example.com/evil` runs `fetch("https://hub.example.com/h/alpha/oc/api/session",
   {method: "POST", credentials: "include", mode: "no-cors", body: "{}"})` and a form POST to
   `https://hub.example.com/api/me`; the hub's access log shows 403 for both and the fake
   OpenCode never received a POST through the hub origin. The mirror: a hub-origin script POSTing to `https://code.example.com/api/session` is
   refused 403 and the fake saw nothing.
4. **The installed PWA's old start URL:** navigating to `https://hub.example.com/hub/` ends on
   `https://hub.example.com/` with the app loaded.
5. **Not framable by others:** a page on a third hostname `https://evil.example.com/` (front-
   served static HTML) framing `https://code.example.com/` and `https://hub.example.com/`: both
   child frames are blocked (no document text readable; `Page.getFrameTree` or the frame's
   isolated-world evaluation fails), while scenario 1's framing by the paired hub works.

Screenshots of B1 (1440×900 and 390×800, light and dark) go to `$DELEGATE_EVIDENCE_DIR`; read
every PNG and say what it shows.

## Verify

While working: `python3 tools/run_tests.py hub.tests.test_h3_acceptance hub.tests.test_h3_browser`.
Once at the end: `python3 tools/run_tests.py` (both suites, in full); the harness requires every
browser module to report `OK` with no skips.

## Out of scope

Any file outside `hub/tests/` (report defects instead); the hostile review script (the
orchestrator writes it); anything live.
