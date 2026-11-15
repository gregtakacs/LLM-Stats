# H3: two origins — the hub at the root of its own, OpenCode at the root of its own

Status: **approved by {owner}** (2026-11-14; rulings in §10). Supersedes h1-design §2 D3 (one origin) and §11.1
(interim `{hub-host}` layout). Everything else in h1/h2/h2c stands unless named here.

## 1. Why

On one origin OpenCode must own `/` (its bundle uses absolute paths and `location.origin` as its
default server; h1-design §7.1), so the hub lives under `/hub/`, and OpenCode's origin-wide service
worker and the hub's share one origin (the 2026-11-14 stale-script hunt). {owner} wants the hub at a
plain root and OpenCode reachable **with or without** the hub.

## 2. Rulings ({owner}, 2026-11-14; binding)

- **R-H3-1. Two origins.** The hub's UI is served at the root of a *hub origin* ({owner}'s:
  `{hub-host}`); OpenCode is served at the root of an *OpenCode origin* ({owner}'s:
  `{opencode-host}`, the existing route). The hub serves both when it fronts OpenCode.
- **R-H3-2. OpenCode with or without the hub.** On the OpenCode origin the hub is a transparent
  gate + relay: what the browser sees there is OpenCode, the same whether the reverse proxy routes
  that hostname to the hub or straight to OpenCode (with its own login + password injection, as
  `{opencode-host}` runs today). Switching is a reverse-proxy route change only; no OpenCode config change,
  no hub config change beyond listing the hostname.
- **R-H3-3. Generic.** No domain, network, or provider name in the repo (examples use
  `hub.example.com` / `code.example.com`). Any reverse proxy, any forward-auth provider (h1 R9),
  and both cookie layouts a provider may use: one cookie for the parent domain, or one per host
  (§5). {owner}'s Traefik/Authentik values live in {infra-repo} and in printed snippets only.

## 3. URL space (replaces h1 D3)

Each public hostname has exactly one **role**, from config (§6). A request's role is decided by
its `Host` (gate step 3, after the 421 check), before any routing.

**Hub origin** (role `hub`):

| Path | Goes to |
|---|---|
| `/`, `/index.html`, static files, `/sw.js`, `/manifest.webmanifest`, `/renew.html` | the hub's UI (today's `hub/static/`) |
| `/api/…` | the hub's own API (today's `/hub/api/…`) |
| `/h/<host>/api/<rest>` | that host's daemon (unchanged) |
| `/h/<host>/oc/<rest>` | that host's OpenCode **API**, every host including the root host (the picker lists and creates sessions same-origin; no CORS anywhere) |
| `/hub`, `/hub/…` | 308 to the same path without the `/hub` prefix (old bookmarks, the installed PWA's old `start_url`), query kept |
| anything else | 404 |

**OpenCode origin** (role `opencode`):

| Path | Goes to |
|---|---|
| `/h/<host>/oc`, `/h/<host>/oc/<rest>` | that host's OpenCode (unchanged; the extra-server URLs in OpenCode's own server list) |
| `/h/_hub/…` | the hub's own files on this origin, only what §5 needs (renewal page); `_hub` can't be a host name (`HOST_NAME_RE` requires a leading letter or digit) |
| any other `/h/…` | 404 |
| everything else, **`/sw.js` included** | the root host's OpenCode, unchanged |

- `/sw.js` is now **relayed** on the OpenCode origin (R-H3-2: identical with or without the hub).
  The no-fetch replacement worker (h1 `ROOT_SW_BODY`) existed only because hub pages shared
  OpenCode's origin; it goes. A browser that has the replacement installed takes OpenCode's worker
  on its next update check.
- The hub origin's `/sw.js` is the hub's own worker, scope `/`, network-first (today's `sw.js`
  with `/hub/` → `/`; its cache name bumps so old caches drop). Registered by absolute URL with an
  explicit scope.
- Chat iframe `src`: `https://<paired OpenCode origin>/server/<base64url(server URL)>/session/<id>`,
  server URL `https://<OpenCode origin>` for the root host, `https://<OpenCode origin>/h/<host>/oc`
  for others (the h1 §7.1 formats, new origin).

## 4. Gate changes (h1 §4)

- **Step 3 (Host)** additionally yields the role. Hostname lists per role must be disjoint (config
  error otherwise).
- **Step 5 (Origin)** tightens from "any public host" to **the request's own origin**:
  `Origin` must equal `https://<this request's Host>`. Why: the two origins are same-site siblings
  and OpenCode renders agent-written content; a page on one must not drive state-changing requests
  or WebSockets on the other. No legitimate cross-origin request remains (the picker goes through
  the hub origin's `/h/<host>/oc`, the iframe's OpenCode talks to its own origin).
  `Sec-Fetch-Site` rule unchanged (`same-origin` or `none`).
- **Body caps (§6.6)**: hub origin — `/api/…` and static 64 KiB, daemon 0, `/h/<host>/oc` OpenCode
  cap; OpenCode origin — everything OpenCode cap except the reserved hub paths (64 KiB). Keyed on
  role + raw path (the 2026-11-14 413 was this table drifting from routing: one table, used by
  both, with a test per row).
- **Framing.** The hub origin's CSP gets `frame-src 'self' <paired OpenCode origin(s)> <auth
  frame origins>`. Responses on the OpenCode origin get the hub's header
  `Content-Security-Policy: frame-ancestors 'self' https://<paired hub origin(s)>` (added, never
  replacing OpenCode's own CSP; browsers ignore `X-Frame-Options` when `frame-ancestors` is
  present, which matters because a proxy may add `X-Frame-Options: SAMEORIGIN`, as {owner}'s Traefik
  does). **Spike first** (§8 step 0): Chrome and Safari, with the proxy's XFO present.
- Everything else in §4 (request line, framing, identity, fail-closed verifier, WebSocket
  re-verify) is unchanged and applies to both roles.

## 5. Sign-in on two origins

Both origins sit behind the same login service, but a provider may scope its cookie per host
({owner}'s Authentik providers are all `forward_single`, `cookie_domain: ''`). Then a fresh browser
signed in on the hub origin is **not** signed in on the OpenCode origin, and the Chat iframe's
first request redirects to the provider *inside the frame*.

- The hub keeps h2's silent renewal (hidden iframe on `/renew.html`, provider origin in
  `auth_frame_origins`) on the hub origin, and gains **the same renewal on the paired OpenCode
  origin** (`/h/_hub/renew.html` there). Before the Chat iframe first loads, and when
  the iframe reports signed-out, the hub page runs the OpenCode origin's renewal frame; the
  provider's existing session makes that a redirect round-trip with no prompt.
- If silent renewal fails (provider session gone, provider refuses framing), the Chat pane shows
  "Sign in to OpenCode" opening the OpenCode origin top-level; the hub never asks for credentials.
- Domain-scoped cookies make this a no-op; the code path is the same.
- The hub never sees, stores or forwards provider cookies across origins (D6 unchanged).

## 6. Config, installer, doctor

`hub.json` (replaces `public_hosts`):

```json
"sites": [
  {"hub": "hub.example.com", "opencode": "code.example.com"},
  {"hub": "hub.lan.example.com", "opencode": "code.lan.example.com"}
]
```

- Each entry pairs one hub hostname with the OpenCode hostname its Chat pane frames. `opencode`
  may be omitted (a hub without OpenCode-on-a-root: Chat links to `/h/<host>/oc` server URLs only
  on that site's paired origin, so omitted = no Chat pane). Every hostname appears once.
- **Migration:** a config with `public_hosts` and no `sites` is refused with a fix line naming the
  new key (no silent single-origin mode: one layout, one gate to review). The installer
  (`--hub-host H` and `--opencode-host H`, repeatable, paired by order; `--public-host` refused
  with the same fix line) writes `sites`; re-running it on an old config rewrites only that key.
- Doctor: per site, the hub origin answers the hub UI, the OpenCode origin answers OpenCode's page
  and `/api/session?limit=1` through the gate, the pairing's framing header is present.
- Printed snippets (Traefik first as one example, then Caddy and nginx, per handoff O1): two
  routers to the hub, one per role, **no** password-injecting middleware on either; plus the
  "without the hub" variant for the OpenCode hostname (straight to OpenCode with the proxy's own
  login and password injection) so switching is copy-paste.
- Docs (`hub-install.md`, `hub-agent-install.md`): the two-origin shape first, generic; the
  provider cookie-scope note (§5); the switch with/without the hub.

## 7. UI changes (mechanical, no new look)

- Every `/hub/` path in `hub/static/` → root-relative (`/app.js`, `/api/me`, …); `manifest`
  `start_url` and `scope` `/`, icons moved accordingly.
- Chat iframe origin from `/api/hosts` (the hub tells the page its paired OpenCode origin; the
  page never derives it from its own hostname).
- The picker's OpenCode calls use `/h/<host>/oc/api/…` for every host, the root host included.

## 8. Steps

0. **Spike (orchestrator, real browser, before any code):** a page on origin A framing origin B
   whose response carries `X-Frame-Options: SAMEORIGIN` **and** `frame-ancestors A`; Chrome
   headless and {owner}'s Safari/Chrome. And: does Authentik's renewal round-trip complete in a hidden
   frame for a second `forward_single` host. Findings recorded here before step 1 runs.
   **Findings (2026-11-14, orchestrator):** Chrome 157 headless, origin A framing origin B: B with
   `X-Frame-Options: SAMEORIGIN` only → blocked (control); B with the same XFO **plus**
   `Content-Security-Policy: frame-ancestors 'self' <A>` (and a second, unrelated CSP header) →
   loads. So the hub's added `frame-ancestors` works through Traefik's XFO. **Not run headless,
   checked at cutover by {owner}:** Safari, and Authentik's silent round-trip for a second
   `forward_single` host inside a hidden frame (the hub origin's own renewal already works live,
   same mechanism). The acceptance step proves the hub side against the fake verifier.
1. **Config + gate + routing** (`hard`): `sites`, roles, Origin = own origin, one body-cap/routing
   table, 308 for `/hub…`, relayed `/sw.js`, framing header, reserved path. Tests per table row and
   the neighbours (wrong-role paths, case and port in Host, a hostname in both roles, Origin of
   the sibling origin, `null` Origin, `/hub` prefix tricks like `/hubx`, `/%68ub/`).
2. **Static + UI move** (light): paths, manifest, worker, Chat iframe origin, picker via
   `/h/<host>/oc`. Browser tests updated to two origins (the test stack serves two hostnames).
3. **Renewal on the OpenCode origin** (`hard`): §5.
4. **Installer, doctor, docs, snippets** (light): §6.
5. **Acceptance** (last, full suites): both origins end-to-end in the browser stack, with-hub and
   a direct-OpenCode control for R-H3-2.

Review: the h1 hostile script grows a two-origin section (sibling-origin CSRF/WS, role confusion,
framing headers), plus a control against `cfb2336` for each gate change.

## 9. Cutover ({owner} runs; asked step by step)

Hub install with the new flags → Traefik: `{hub-host}` unchanged (to the hub), `{opencode-host}` router service
switched to the hub and its password middleware removed → doctor → {owner} re-adds extra servers in
OpenCode's settings on `{opencode-host}` (OpenCode's server list is per origin; the old list on `{hub-host}` is
left behind) → rollback is the one-line router switch back.

## 10. Owner rulings ({owner}, 2026-11-14, answering the draft's questions)

1. **Old single-origin layout: dropped.** An old `public_hosts` config is refused with a fix line;
   `/hub…` URLs 308 to the root.
2. **Per-host provider cookies stay; the hub renews the OpenCode origin silently** (§5). No
   Authentik change.
3. **OpenCode's own service worker runs on the OpenCode origin**; the hub relays `/sw.js` there
   untouched (R-H3-2).
4. **`{opencode-lan-host}` stays direct to OpenCode** for now; pairing it with a hub hostname later is a
   config + proxy change only.
