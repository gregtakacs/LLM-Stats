# H3w step 3: silent renewal on the paired OpenCode origin, and its sign-in link

## Goal

Make the OpenCode origin sign in the same way the hub origin does, without a second
session mechanism. The existing silent-renewal frame (`renew.js`/`renew.html`, h2 §5) is
reused **on the OpenCode origin** by serving it from the reserved path `/h/_hub/renew.html`
(step 1's reserved route), framed by OpenCode's own top-level page. Its CSP must let
OpenCode's origin frame it, and it must post its result only to its own OpenCode origin.
When that renewal cannot complete, the OpenCode UI shows a single "Sign in to OpenCode"
action that is a **top-level navigation** to the hub origin's sign-in (the existing
`/api/login`→verifier flow), never a nested frame. This is step 3 of
`docs/h3-design.md` §8 and §5; it is `"hard": true` because it moves auth/session and
framing onto a second origin.

Binds: `docs/h3-design.md` §5 (the both-origin renewal, the reserved `/h/_hub/` path, the
failure → top-level link), §4 (framing: the appended `frame-ancestors` from step 1 is what
lets the hub frame be loaded, and the hub's `frame-src` from step 1 already lists the
paired opencode origin so the opencode page can be framed on the hub), §3 (reserved
`/h/_hub/…`), §10.4/§10.5.

## Read first

- `docs/h3-design.md` §5 **in full**, §3, §4, §10.4, §10.5, §6.6 (`/h/_hub/` cap).
- `docs/specs/h3w-1-roles-routing.md` (the reserved route + `csp_for` + the appended
  `frame-ancestors`) and `h3w-2-ui-move.md` §the two-hostname stack — both are already on
  this branch.
- `hub/static/renew.js`, `renew.html`, `api.js`, `data.js` — the current renewal and how it
  posts its result, and where the "sign in" affordance lives.
- `hub/api.py` — how `renew.html` is served now, `NO_STORE_NAMES`, `csp_for`; `hub/proxy.py`
  `/h/_hub/` route from step 1.
- `hub/tests/test_h2_browser.py` (the two-hostname stack you extend), `test_h2c_browser.py`
  (the renewal-over-browser pattern to copy), `test_ui.py`.
- `~/.config/opencode/rules/verify-ui.md` — the failure-state UI you add needs the four
  screenshot modes.

## Contract

### Files

Modify: `hub/api.py` (serve `renew.html` at `/h/_hub/renew.html` on the opencode role, with
the correct CSP for that context), `hub/static/renew.js`/`renew.html` (make the frame and
its `postMessage` target origin-aware so it works at both `/renew.html` on the hub and
`/h/_hub/renew.html` on the OpenCode origin), the OpenCode-side top-level page integration
that shows the sign-in link (this is the hub's own served page on the opencode role if the
hub injects it; if it is purely OpenCode's page, then only the link target/`<a>` contract
is specified here and the wiring is a documented snippet — decide from what step 2's fake
OpenCode shows and record the choice), `hub/tests/test_ui.py`, `test_h2c_browser.py`, and
new `hub/tests/test_opencode_renew.py`. Add no new endpoint beyond `/h/_hub/renew.html`;
`/api/login` is unchanged and reused.

### Behaviour

- `/h/_hub/renew.html` on the opencode role serves the same document as the hub's
  `/renew.html`, `no-store`, and its `Content-Security-Policy` `frame-ancestors` permits
  `'self'` (the opencode origin) and the paired hub origin, and its `frame-src`/`connect-src`
  still only allow the verifier/auth origins from config. It is reachable on the opencode
  role only; on the hub role `/h/_hub/…` is a 404 (assert it).
- The frame, once loaded, runs the identical silent-renewal handshake and reports the
  result to its **own** origin (`window.parent.postMessage(..., location.origin)`), so the
  OpenCode top-level page receives it exactly as the hub page receives its own frame's
  message today.
- On success the OpenCode origin now has its provider/session cookie (same as the hub
  origin would), and the Chat/session UI on that origin proceeds — proving R-H3-2: the
  with-hub OpenCode origin and a direct OpenCode origin behave the same.
- On failure (no cookie / verifier refused / timeout) the OpenCode UI renders exactly one
  affordance: a link labelled **"Sign in to OpenCode"** that is a top-level navigation
  (`target="_top"`, no `sandbox`-blocked scripting) to the hub origin's `/api/login` flow.
  It is never an iframe. Empty/loading/error states follow `verify-ui.md`.

### Tests

- `test_ui.py` (static): `renew.html` referenced/served at `/h/_hub/renew.html`, the link
  text is exactly `Sign in to OpenCode`, it is an `<a>` with `target="_top"` to a
  `/api/login`-derived URL, and there is no `frame`/`iframe` around it.
- `test_opencode_renew.py` (socket): `/h/_hub/renew.html` on the opencode host → 200 with
  the expected CSP and `no-store`; on the hub host → 404; the body-cap row for `/h/_hub/…`
  is 64 KiB (against step 1's table); the reserved path never proxies to OpenCode.
- Browser (`test_h2c_browser.py` extend, over the two-hostname stack): with a provider
  cookie present for the opencode host, the framed renewal sets the session and Chat loads
  with **no** visible sign-in prompt; with the cookie **cleared** for that host, the
  failure state shows the single "Sign in to OpenCode" link and clicking it does a top-level
  navigation to the hub sign-in. Assert (no request log) the frame is same-opencode-origin.

## Acceptance

`python3 tools/run_tests.py` (both suites, full — hard step). Screenshots per
`verify-ui.md`: the OpenCode-origin renewal success and failure states at **390×800** and
**1440×900**, light and dark, **every PNG read**, under `$DELEGATE_EVIDENCE_DIR`. Scope
guard against the previous step's branch.

## Out of scope

Installer/doctor/docs (step 4), the full with/without-hub control matrix and hostile sweep
(step 5), any change to the verifier or `/api/login` itself.

## Notes

If the OpenCode top-level page is not the hub's to inject (a genuine direct-OpenCode
control in step 5 must work with an unmodified OpenCode), then the sign-in link lives only
where the hub serves/frames it, and the direct-OpenCode case is documented as "no hub
renewal frame; the provider signs you into OpenCode directly" — record which reading the
fake OpenCode from step 2 supports, under DEVIATIONS if it differs from the spec's literal
wording.
