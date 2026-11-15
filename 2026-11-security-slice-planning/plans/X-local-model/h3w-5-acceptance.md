# H3w step 5: two-origin acceptance — both origins end to end, with-hub and direct-OpenCode control, hostile sweep

## Goal

Prove the whole slice against a real browser over the two-hostname stack, and prove it
**two ways** so R-H3-2 is not merely asserted: (1) the OpenCode hostname routed **via the
hub**, and (2) the same OpenCode hostname routed **directly to OpenCode** (the hub out of
the path), with the observable browser behaviour identical. Then a **hostile two-origin
sweep** that attacks every guard step 1–3 installed from every wrong angle, and a control
against the pre-H3 commit for anything that can only be shown by contrast. This is
`docs/h3-design.md` §8 step 5 and §7's acceptance bar; it is `"hard": true` and the last
step, so it runs both full suites.

Binds: `docs/h3-design.md` §2 (all three rulings, demonstrated not described), §3, §4, §5,
§10. New module only; no product-code change except a fix if acceptance finds a bug (then
name it in the report).

## Read first

- `docs/h3-design.md` §2, §3, §4, §5, §7, §8 step 5, §10 — the acceptance criteria.
- `docs/specs/h3w-design.md` §5 (the stack) and each prior step spec's Acceptance.
- `hub/tests/test_h2_browser.py` (the two-hostname `BrowserStack` + fake OpenCode you build
  on), `test_h2c_browser.py`, `PageSession`, `test_h1_acceptance.py`, `test_h2_acceptance.py`
  (the acceptance-module idiom: a scenario per ruling, fixed-port-free, `load_tests`).
- `hub/tests/httputil.py` (the `SITES`/pair fixtures from step 1), `hub/gate.py`,
  `hub/proxy.py`.

## Contract

### Files

Create `hub/tests/test_h3_acceptance.py`. Extend `hub/tests/test_h2_browser.py`'s stack only
as far as the direct-OpenCode control needs (a mode that puts OpenCode in front without the
hub, reusing the same fake). Touch product code **only** if acceptance finds a real bug; if
you do, keep it inside step 1/3's scope and call it out explicitly in your report.

### Acceptance scenarios (each a test, in a real browser)

1. **Hub origin, signed in.** Load `https://<hub>/` → UI at root, no `/hub` in any request,
   the service worker registers at `/sw.js` scope `/`, the manifest installs, Chat opens the
   paired OpenCode origin and a session runs; picker uses same-origin `/h/<host>/oc`.
2. **OpenCode origin via the hub (with-hub).** `https://<opencode>/` → transparent OpenCode,
   `/sw.js` is OpenCode's own (relayed, not the hub body), the renewal frame at
   `/h/_hub/renew.html` signs the origin in silently, Chat/session work, the appended
   `frame-ancestors` allows the hub to frame it.
3. **Direct-OpenCode control (without hub).** Same OpenCode app served with the hub out of
   the path; the **observable browser behaviour of scenario 2's OpenCode surface is
   identical** — same headers OpenCode itself sets, same `/sw.js`, same app boot. The only
   difference allowed is the hub-added `frame-ancestors`/renewal affordance, which is
   absent by definition when the hub is not in front; assert exactly that and nothing more.
4. **Cross-host confusion refused.** On the hub origin, a request whose `Origin` is the
   paired OpenCode host (sibling) is 403 for POST/WS; `/api/me` with an opencode `Host` is
   421; a body above the role's cap is 413 with the cap coming from the table.
5. **Hostile two-origin sweep** (assert no leak, no bypass, no downgrade on either role):
   `Host` wrong-case, trailing-dot, `:443`, an unexpected port; `Origin` `null`, `http://`,
   a third host, missing-on-WS-upgrade; `/h/_hub/` requested on the **hub** role (must 404);
   `/h/` traversal tricks (`/h/../`, encoded `%2e%2e`); the `/hub` prefix tricks `/hubx`,
   `/%68ub/`, `//hub/`, `/hub/..`; a `Sec-Fetch-Site: cross-site` non-GET; oversized body on
   every capped prefix on both roles; and each refusal never forwards upstream (assert the
   fake OpenCode/daemon saw nothing).

### Control (pre-H3 contrast)

For each rule that can only be shown by a behavioural difference (the sibling-Origin flip
from allowed→403, and `/sw.js` relay vs h1's replacement body), run the **same** request
against the previous step's branch / the `h3w-base` commit and show the two answers differ
in the expected direction. Record commit SHA in the report.

## Acceptance

`python3 tools/run_tests.py` (both suites, full). Scope guard:
`! { git diff --name-only h3w-base; git ls-files --others --exclude-standard; } | grep -vE
'^(docs/specs/h3w-|hub/|daemon/tests/test_install_docs\.py)'`. Browser scenarios produce
screenshots per `verify-ui.md` (390×800 and 1440×900, light+dark) for scenarios 1–3, every
PNG read, under `$DELEGATE_EVIDENCE_DIR`.

## Out of scope

Any new product feature; any change to a guard's **behaviour** (this step verifies and, at
most, fixes a found bug). {owner}'s cutover (h3 §9) is not run here.

## Notes

If a browser scenario cannot run because Chrome/the stack is unavailable in this sandbox,
report it under NOT VERIFIED with the exact error — do not mark it passed and do not add a
skip to the suite.
