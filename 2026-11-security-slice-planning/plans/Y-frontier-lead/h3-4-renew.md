# H3 step 4: silent renewal on the paired OpenCode origin, and "Sign in to OpenCode"

`"hard": true`: the session flow and a new hub-authored route on the OpenCode origin. Design
step 3 (`docs/h3-design.md` §5). A provider may scope its cookie per host, so a browser signed in
on `hub.example.com` is not signed in on `code.example.com`; the hub page renews that origin
silently with a hidden frame, the same way h2 renews its own, and the frame **tells the page it
landed** with a `postMessage` (a cross-origin frame's `load` event says nothing about where it
landed).

## Read first

- `docs/h3-design.md` §3 (`/h/_hub/`), §4 (framing), §5 (binding); `docs/h2-design.md` §5 (all:
  mechanism, cadence, limits, the CSP key).
- `hub/routes.py` (row O1), `hub/api.py` (`_send`, `serve`, `CSP`), `hub/__main__.py`
  (`build_server`: what is precomputed per hostname), `hub/gate.py` (`respond`: the OpenCode-role
  framing header).
- `hub/static/renew.js` (all), `hub/static/app.js` (`startRenewal` hooks, `reloadChat`, the
  chat-activity tracking), `hub/static/views/chat.js` (`chatOrigin`, `render`),
  `hub/static/views/sessions.js` (where `chatSrc` is set), `hub/static/index.html`
  (`#chat-notice`, `#chat-frame`).
- `hub/tests/browser_front.py` (the front: routes, jar), `hub/tests/test_h2_browser.py`
  (`BrowserStack`, `PageSession`), `hub/tests/test_two_origins.py`, `hub/tests/test_ui.py`.

## Contract: the server (`/h/_hub/` on the OpenCode role, row O1)

- Exactly two resources exist; everything else under `/h/_hub` stays 404 (no file lookup, no
  directory, never anything from `hub/static/`):
  - `GET|HEAD /h/_hub/renew.html` (any query) → 200, `Content-Type: text/html; charset=utf-8`,
    body exactly
    `<!doctype html><meta charset="utf-8"><title>ok</title><script src="/h/_hub/renew.js"></script>ok`
  - `GET|HEAD /h/_hub/renew.js` (any query) → 200, `Content-Type: text/javascript; charset=utf-8`,
    body exactly `parent.postMessage("{project}-renewed", "https://<paired hub hostname>");\n` with
    the hostname paired with **this request's** OpenCode hostname, written with `json.dumps`
    (precomputed per OpenCode hostname at startup).
  - Both: `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, `Connection: close`,
    exact `Content-Length`, and one `Content-Security-Policy: default-src 'none'; script-src
    'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'self' https://<paired hub
    hostname>` in addition to the step-2 framing header every OpenCode-role response gets.
  - Other methods → 405; an upgrade → 400; the gate runs first as everywhere (a cookie-less
    request is the gate's 401, which is what makes the provider round-trip happen behind a
    forward-auth proxy).
- On the hub role, `/h/_hub/…` stays H5 (404).

## Contract: the page (`hub/static/renew.js` and its callers)

1. `renewOpenCode(origin)` (exported): one in-flight promise per origin. It appends a hidden
   iframe exactly like `_iframeRenew` (`width`/`height` 0, `aria-hidden="true"`,
   `tabindex="-1"`) but with `sandbox="allow-scripts allow-same-origin"` and
   `src = origin + "/h/_hub/renew.html?t=" + Date.now()`. It resolves **true** only on a
   `message` event with `event.origin === origin`, `event.source === frame.contentWindow` and
   `event.data === "{project}-renewed"`; **false** when `OC_LOAD_GRACE_MS = 2000` pass after the
   frame's `load` with no such message, or `FRAME_TIMEOUT_MS` after the start. The frame and the
   listener are always removed. No other field of the message is read; nothing is ever posted
   back. `origin` is only ever the value of `chatOrigin(...)`.
2. `ensureOpenCode(origin)` (exported): resolves true at once when the last OpenCode-origin
   success is less than `RETURN_AFTER_MS` old, else returns `renewOpenCode(origin)`.
3. **Before the Chat iframe gets any `src`** (the first one after `/api/hosts`, a chosen or new
   session, `reloadChat`), the page awaits `ensureOpenCode(origin)`. True → set the `src` as step 3
   does. False → leave the iframe as it is (no `src` yet, or its current one) and show the notice
   (5). The wanted `src` is remembered and applied when a later renewal succeeds.
4. **Cadence**: the existing interval tick and the visibility-return check (h2 §5.2) also run
   `renewOpenCode(origin)` after the hub's own renewal when the page is paired; a hub
   `renewAfterFailure()` success does too. A success after a failure hides the notice and applies
   the remembered `src`.
5. **Notice** (failure): `#chat-notice` shows `Signed out of OpenCode. ` followed by a link
   `Sign in to OpenCode` (`<a>` built with `createElement`/`textContent`, `href = origin + "/"`,
   `target="_blank"`, `rel="noopener noreferrer"`). The hub never asks for credentials. While the
   iframe has no `src` it stays hidden. No new CSS: the notice keeps the `empty-note` class; a
   link inside inherits the page's existing link style.
6. Domain-scoped cookies make the renewal a quick success: same code path.
7. The service worker is unchanged (the OpenCode origin is another origin; it never sees those
   requests). The hub's own renewal (`/renew.html`, `/api/me`) is unchanged.

## Tests (required; then look beyond this list for the neighbouring cases)

- **Server** (add to `test_two_origins.py` or a new `test_oc_reserved.py`): both resources'
  exact bodies and headers on `code.example.com`, and `renew.js` naming
  `https://hub.local.example.com` on `code.local.example.com`; HEAD; `?t=1`; POST (own Origin)
  → 405; upgrade → 400; cookie-less → 401 (gate first, no body of ours); 404 for
  `/h/_hub`, `/h/_hub/`, `/h/_hub/renew.html/`, `/h/_hub/renew.htm`, `/h/_hub/RENEW.HTML`,
  `/h/_hub//renew.html`, `/h/_hub/renew.html;x`, `/h/_hub/%72enew.html`, `/h/_hub/index.html`,
  `/h/_hub/sw.js`, `/h/_hub/app.js`, `/h/_hubx/renew.html`; on the hub role
  `/h/_hub/renew.html` and `/h/_hub/renew.js` → 404.
- **Static** (`test_ui.py`): the constants; the sandbox value; the listener compares
  `event.origin`, `event.source` and `event.data` (all three, strict equality); no
  `postMessage(` call anywhere in `hub/static/`; no `"*"` target origin; the notice is built
  without `innerHTML`; the frame is removed on every path.
- **Browser** (new `hub/tests/test_h3_renew_browser.py`, on the front): add a **fake provider**
  (a small HTTP server in the module, routed by the front as `idp.example.com`) and a front option
  `forward_auth: set[hostname]`: a paused request for such a host with no jar entry is answered
  with `Fetch.fulfillRequest` 302 to `https://idp.example.com/auth?rd=<quoted original URL>`
  (the reverse proxy's forward-auth redirect). The provider, when its `session` flag is on, puts
  `idp_session=…` in the front's jar for `rd`'s host and answers 302 to `rd`; when off it answers
  a 200 login page with `X-Frame-Options: DENY`. The stack's `hub.json` lists
  `"auth_frame_origins": ["https://idp.example.com"]` (the hub page's `frame-src` is checked on
  every hop of the frame's redirect chain, exactly as in production). Scenarios:
  1. per-host cookies (jar: hub only), provider session on: the chat frame gets
     `https://code.example.com/` with no user action; the hub's access log has exactly one
     `/h/_hub/renew.html` on the OpenCode host before the first chat request; no notice;
  2. provider session off: the notice shows the exact text and link `href`
     `https://code.example.com/`, the chat iframe has no `src`, the renewal frame is gone from the
     DOM; then the provider session on and a visibility return (dispatch `visibilitychange` with
     `Emulation.setFocusEmulationEnabled`/`Page.setWebLifecycleState` or the page's exported
     hook) → notice hidden, chat frame loaded;
  3. a forged message: while a renewal is pending against a provider that never answers, the hub
     page posts `"{project}-renewed"` to itself (`window.postMessage(…, "*")`) → the renewal still
     fails;
  4. domain cookies (jar: both hosts): success without the provider ever being asked;
  5. two `renewOpenCode` calls at once → one renewal frame.
  **Controls**: scenario 1 must fail on step 3's code (no renewal: the frame lands on the
  provider); scenario 3 must fail with a listener that checks only `event.data`. Say how you
  checked both.

## Screenshots (`verify-ui.md`)

The notice at 1440×900 and 390×800, light and dark. Read every PNG; nothing else may look
different from step 3.

## Verify

While working: `python3 tools/run_tests.py hub.tests.test_two_origins hub.tests.test_ui
hub.tests.test_h3_renew_browser`. Once at the end: `python3 tools/run_tests.py` (both suites);
the harness requires the browser modules to report `OK` with no skips.

## Out of scope

`hub/config.py`, `hub/verifier.py`, `hub/wsrelay.py`, `hub/streams.py`; any change to how the
gate authenticates; the hub origin's own renewal; `app.css`; installer, doctor, docs (step 5).
