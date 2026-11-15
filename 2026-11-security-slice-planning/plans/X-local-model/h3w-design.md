# H3 design (planning): two origins — the hub at the root of its own, OpenCode at the root of its own

Planning layer for slice **H3w** (the worker-facing re-cut of the approved
[`docs/h3-design.md`](../h3-design.md)). That document is the **contract** and is
binding: its §2 rulings **R-H3-1/2/3**, its §3 URL space, §4 gate changes, §5 sign-in,
§6 config/installer/doctor, §7 UI moves, §10 owner rulings and the §8 step-0 spike
findings are decided and are **not re-opened here**. This file only splits that
contract into verifiable worker steps, records the sequence and the per-step scope, and
adds the implementation detail a worker needs that the design leaves implied. The chain
is [`h3w-chain.json`](h3w-chain.json); one spec per step at `h3w-<n>-<slug>.md`.

No product code is written by this design. Every file below is created/changed by a step.

## 1. The slice in one breath

Today the hub lives at `/hub/…` on a single origin and OpenCode owns `/` on that same
origin (h1 §2 D3, the interim `{hub-host}` layout of §11.1). H3 gives each public hostname
exactly one **role** from config: a **hub origin** where the hub's UI/API live at the
root, and a **paired OpenCode origin** where the hub is a transparent gate + relay so
what the browser sees there is OpenCode — identical whether the reverse proxy sends that
hostname to the hub or straight to OpenCode (R-H3-2). Sign-in on two origins is done by
running the existing silent-renewal frame on **both** origins (§5). The old single-origin
layout is **dropped**: a config with `public_hosts` and no `sites` is refused with a fix
line (R-10.1).

## 2. Why five steps, and this order

The design's §8 outline is honoured. The one deliberate change of sequence: the
`/hub…` **308** (which §8 step 1 lists) is implemented in **step 2** together with the
static move, not in step 1. Reason: a 308 on `/hub/api/…`/`/hub/<static>` breaks the
shipped UI the instant it lands (every fetch in `hub/static/api.js` uses
`redirect: "manual"`, so a 308 answers `opaqueredirect` → the Sign-in screen), so the
redirect and the files it redirects to must move in the same step to keep **every step of
the chain independently green** (handoff §4/§5). The 308's own behaviour is exactly §3's.
Recorded under DECISIONS in step 1's spec; a reviewer who prefers it in step 1 should
merge steps 1 and 2, which would exceed the ~1500-line step budget.

| # | spec | hard | one coherent change |
|---|---|---|---|
| 1 | [`h3w-1-roles-routing.md`](h3w-1-roles-routing.md) | **true** | config `sites` + gate role + Origin=own-origin + one caps/routing table for both roles + framing header + relayed `/sw.js` + reserved `/h/_hub/`. **Both** the new root layout and the old `/hub/…` tree are served, so the shipped UI keeps working. |
| 2 | [`h3w-2-ui-move.md`](h3w-2-ui-move.md) | false | static/manifest/worker to root-relative, Chat iframe origin from `/api/hosts`, picker via `/h/<host>/oc`, **then** `/hub…`→308 and drop the dual `/hub` serving; browser stack serves two hostnames. |
| 3 | [`h3w-3-opencode-renew.md`](h3w-3-opencode-renew.md) | **true** | §5: the same silent renewal on the paired OpenCode origin (`/h/_hub/renew.html`), its failure → "Sign in to OpenCode" top-level link. |
| 4 | [`h3w-4-installer-docs.md`](h3w-4-installer-docs.md) | false | §6: installer flags `--hub-host`/`--opencode-host`, `sites` written + old `public_hosts` migrated, doctor per-site, the with/without-hub proxy snippets, both docs. |
| 5 | [`h3w-5-acceptance.md`](h3w-5-acceptance.md) | **true** | both origins end to end in the browser stack, with-hub **and** a direct-OpenCode control for R-H3-2; hostile two-origin sweep; full suites. |

`hard: true` on step 1 (it is the gate/routing/body-cap/Origin/framing boundary), step 3
(it is auth/session and framing on a second origin), and step 5 (it is the last step and
sweeps every guard). Steps 2 and 4 are mechanical UI/installer/docs moves behind step 1's
already-green gate, so their verify runs their own modules plus the scope guard; steps 1,
3 and 5 run both suites in full (AGENTS.md test policy).

## 3. What step 1 must settle for everyone else (the shared seams)

These are the interfaces the later steps build on; they are specified once here so the
specs do not drift.

**Config** (`hub/config.py`). Replace key `public_hosts` with `sites`: a non-empty JSON
array of objects, each `{"hub": "<dns name>"}` with optional `"opencode": "<dns name>"`.
Both names use the existing `_public_host_ok` rule (a bare lowercase DNS name, no port).
Every hostname appears **exactly once across all entries and both fields** (so no host
carries two roles, and one name is never in two sites) → otherwise `ConfigError`. Each
`hub` field is required; `opencode` may be absent (a hub with no Chat). `HubConfig` keeps
`public_hosts` **as a derived read-only property** = every site hostname (so call sites
that only need the membership set survive unchanged), and adds `sites: tuple[Site, ...]`
plus helpers `role_of(host) -> "hub"|"opencode"`, `hub_hosts`, `opencode_hosts`, and the
pairing `opencode_for(hub_host)` / `hub_for(opencode_host)` (→ the paired name or `None`).
A doc with `public_hosts` and no `sites` → `ConfigError` whose message names the new key
as the fix, never echoes a value. `sites` with no `public_hosts` is the accepted form.

**Gate step 3 yields the role** (`hub/gate.py`). `_step_host` additionally returns the
request's **self-origin** string used by step 5: `https://` + the Host header normalised
as a *browser origin* — lowercased, one trailing dot dropped, an explicit `:443` dropped,
**any other port kept** (so the browser test stack on an ephemeral port still matches its
own `Origin`). Membership is checked against the port-stripped name as today; a name not
in the (single) role list it is configured for → **421**. Role confusion is a 421 (an
opencode host asked to serve `/api/me`) — same status as an unknown host, so the answer
does not reveal which role a host has.

**Gate step 5 — Origin is the request's own origin.** For every method other than
GET/HEAD, and for **every WebSocket upgrade including GET**, `Origin` must equal
`https://<this request's Host>` (the self-origin above) → else **403**. A sibling
`https://<other public host>` — same site, the other role — is now refused (it was
accepted under h1 §4.5). Missing Origin on those requests → 403. `null` → 403.
`http://…` → 403. `Sec-Fetch-Site` rule unchanged (`same-origin` or `none`). No
legitimate cross-origin request survives (R-H3-2 §4's rationale; the picker uses
same-origin `/h/<host>/oc`, the Chat iframe's OpenCode talks to its own origin).

**One table for routing and body caps.** A single module-level route/cap table keyed on
`(role, raw path prefix)` produces *both* the routing decision (which upstream / hub
handler / status) and the `body_cap` for that request. `gate.body_cap(raw_target, role)`
reads that table, never a parallel `if` chain (the 2026-11-14 413 was a table drift).
The table is exactly §3's two role tables plus §6.6's caps:

| role | path (raw, literal prefix) | goes to | body cap |
|---|---|---|---|
| hub | `/`, static, `/sw.js`, `/manifest.webmanifest`, `/renew.html`, `/icons/…`, `/views/…` | hub UI/worker (`hub/api`), worker at `/sw.js` | 64 KiB (`CAP_HUB_API`) |
| hub | `/api/…` | hub API | 64 KiB |
| hub | `/h/<host>/api/…` | that host's daemon | 0 (`CAP_DAEMON`) |
| hub | `/h/<host>/oc/…` (and `/h/<host>/oc`) | that host's OpenCode, **every host incl. root** | 32 MiB (`CAP_OPENCODE`) |
| hub | `/hub`, `/hub/…` | **308** to same path minus `/hub` prefix, query kept | (n/a) |
| hub | anything else | 404 | 64 KiB |
| opencode | `/h/<host>/oc`, `/h/<host>/oc/<rest>` | that host's OpenCode | 32 MiB |
| opencode | `/h/_hub/…` (and `/h/_hub`) | hub's reserved files on this origin (`hub/api`, only `/h/_hub/renew.html`) | 64 KiB |
| opencode | any other `/h/…` | 404 | 32 MiB |
| opencode | **`/sw.js` and everything else** | root host's OpenCode, relayed unchanged | 32 MiB |

`_hub` cannot be a host name (`HOST_NAME_RE` needs a leading letter/digit), so the
reserved segment is unreachable by host routing by construction; a test asserts it.
`proxy.route_for(target, …, root_host)` gains the role parameter; the catch-all OpenCode
route only applies on the **opencode** role — on the hub role the catch-all is a 404. The
old root-OpenCode `ROOT_SW_PATH`/`ROOT_SW_BODY` replacement worker (h1) is **removed**:
on the opencode role `/sw.js` is relayed to OpenCode untouched (R-10.3), and on the hub
role `/sw.js` is the hub's own worker (step 2's file).

**Framing.** Hub-origin responses carry `frame-src 'self' <every paired opencode origin,
in config order> <auth_frame_origins…>` (the §5.6 `csp_for` generalised to take the
paired OpenCode origins too — the origins are derived from config, never from the request
Host, so a request cannot widen its own `frame-src`). Every response relayed on the
**opencode** role gains a hub-added header
`Content-Security-Policy: frame-ancestors 'self' https://<paired hub origin(s)>`,
**appended** as a second CSP header, never merged into OpenCode's own (browsers take the
most restrictive of multiple CSP headers, and the §8 spike proved Chrome loads through a
proxy-added `X-Frame-Options: SAMEORIGIN` when such a `frame-ancestors` is present). No
`X-Frame-Options` is ever added by the hub.

**Test-fixture migration (step 1, `hub/tests/httputil.py`).** `PUBLIC_HOSTS` becomes
`[HUB_HOST, OPENCODE_HOST]` with `HUB_HOST = "hub.example.com"`,
`OPENCODE_HOST = "code.example.com"` (R-H3-3: generic names only),
`SITES = [{"hub": HUB_HOST, "opencode": OPENCODE_HOST}]` and a second LAN pair
`HUB_HOST2/OPENCODE_HOST2` for the disjointness/both-roles tests; `write_config` writes
`sites`. `self.host` stays `PUBLIC_HOSTS[0]` (the hub host, port-less, so the default
origin stays self). Every existing test that hits a role-restricted path with the wrong
role's Host, or that sends a now-forbidden sibling `Origin`, is updated to match its
path's role — that is part of step 1, not a later step. `ws_upgrade_lines`'s default
`origin` remains `https://` + `PUBLIC_HOSTS[0]` (self).

## 4. Screenshots and UI (steps 2, 3)

H3 moves paths; it adds **no new visual design**. Where a step changes a thing a human
sees it follows `~/.config/opencode/rules/verify-ui.md`: screenshots at **390×800** and
**1440×900**, **light and dark**, and **every PNG read**. New behaviour that a static
grep can prove (root-relative paths, manifest `start_url`/`scope`, the never-cache list)
is proved in `hub/tests/test_ui.py`; only state-dependent UI (Chat iframe loads from the
paired origin, the renewal states) is proved in the real browser over the two-hostname
stack.

## 5. The test stack on two hostnames (steps 2, 3, 5)

`hub/tests/test_h2_browser.py`'s `BrowserStack` today serves one hostname (`HOST`) and
launches Chrome with `--host-resolver-rules=MAP <HOST> 127.0.0.1`. Step 2 widens it to a
**site pair**: a hub hostname and its paired OpenCode hostname, both mapped to loopback
(`--host-resolver-rules=MAP <hub>,<opencode> 127.0.0.1`), `sites=[{hub,opencode}]`, the
OpenCode role served by a **fake OpenCode** the stack owns (the module already fakes the
verifier; it now also fakes an OpenCode upstream so `/`, `/sw.js`, `/api/session` answer
on the opencode host). `PageSession` gains the second origin's cookie scope so a test can
model per-host provider cookies (§5). Later steps reuse the pair; nobody re-invents it.

## 6. What H3w does **not** touch

`daemon/` at large (only `daemon/tests/test_install_docs.py`'s expectations about the hub
docs move, in step 4), the verifier's request shape, the WebSocket relay internals, the
SSE re-verify mechanism, the graph/projects/history views' look, and any reverse-proxy or
Authentik value (R-H3-3 — those live in {infra-repo} and printed snippets only). {owner}'s
cutover (§9) is run by the orchestrator, not by any step.
