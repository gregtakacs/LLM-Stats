# A2 step 7 design — the unified picker UI (a2p)

Chain `a2p` · repo `../..` · base `a2-steps-6-8` · gate `python3 tools/run_tests.py` · step 7 of
the A2 plan (`docs/specs/a2-design.md` rulings 24–26; rulings 9/24/25 are owner rulings and are
implemented literally). Three steps: `a2p-1-bar-controls` (hard), `a2p-2-admin-rows-security`
(hard), `a2p-3-browser-shots` (light — it owns no product-code boundary; the URL/DOM boundary is
guarded in the first two). All facts below were re-grounded against `4c60732`, which includes
`6eed48f` (the toggle-restore commit).

## 1. What the base actually is

- **There is no `<select>` in the chat view.** `hub/static/index.html` l.55-65:
  `#chat-project` is a `<button>` (`aria-haspopup="listbox"`, `aria-controls="session-picker"`,
  `aria-expanded="false"`) that **is** the picker toggle; the sibling
  `#chat-project-clear` ("All") resets the filter; `#session-picker` is a
  `role="listbox"` popover with `hidden` set. `6eed48f` restored exactly this shape.
- `hub/static/views/sessions.js` builds the picker: a "All projects" option plus one option per
  project, each a `.session-row` span with `textContent = p.title` (l.197) inside a
  `.picker-row` wrapper; activation = `pointerdown`/`keydown Enter` →
  `selectProject(id)` + `closePicker()` (l.266-273). Project **selection never opens** the
  dropdown — the behaviour ruling 24 keeps. The document click handler (l.45-55) closes the
  picker when the click hits outside `CLICK_AWAY_EXEMPT`; that selector constant is currently
  `"#chat-project, #session-picker"` — step 7 widens it to
  `"#chat-project, #chat-claude-new, #chat-admin-reason, #session-picker"`, the exact literal
  pinned by `test_click_away_exempt_selector_pinned`. `#chat-admin` does not exist yet.
- The Claude start button lives in the launch section: `devButton("claude-start", …)` in
  `views/claude.js` `paintSection` (l.227); its disabled states implement a2a §7's copy already
  ("Needs the admin origin: A1 phase 2" l.153, "Not in broker.json" l.627), and a change listener
  on `#claude-modes` (claude.js l.735) drives the dispatch selector `#session-picker [data-claude]`
  (l.723) — the selector widens in step 7; the behaviour rule itself is unchanged.
- `state.launcher` (null before the first poll) and `state.launcherStale` are maintained by
  running.js's 10 s poll (l.49-60, 267-280) with `launcherFetchInFlight` dedupe — one poller per
  page; consumers import the state. The pill (`#launcher-state`) and `#launcher-refresh-note`
  ("Last checked …"/error) stay untouched.
- `admin_origin` is a per-host row field of `/api/hosts` (`hub/api.py` l.598-630: the settings
  value copied onto every row; row keys exactly `{id, label, mode, reachable, error,
  admin_origin}` — pinned by `test_ui.py` l.484). It is **never** in `/api/config` and there is no
  `window.hubConfig.admin_origin`; `app.js renderAdminLink` (l.147-154) reads the setting today
  and injects the raw value into an href with no validation — step 7 fixes that by reusing the
  new shared validator (§5.4).

## 2. The ruling, implemented literally (rulings 9 + 24)

The chat-view bar gets **exactly two controls**, always visible, in this order:
`#chat-project` (the unified picker control; label = selected project display name or
"All projects") then `#chat-claude-new`.

**The dropdown opens only from the control.** Selecting a project never opens it and closes an
open one (6eed48f preserved exactly); nothing outside the control toggles it; outside click and
Escape close it. Inside the dropdown, "New OpenCode session" (the New-session row, exact copy)
sits **above** the admin rows ("OpenCode first, then admin inside the dropdown").

**Ineligible admin row: the reason goes to the bar, not a popup, and not the dropdown.**
Activating `#chat-admin` while ineligible (or while the stored origin fails validation) must
never navigate and never calls `window.open`; it must not open the dropdown either — opening on
that activation would be a second control path into it (ruling 24: the dropdown opens only from
its own control). The reason therefore appears in exactly one place: the bar-level line
`#chat-admin-reason`, `role="status"`, hidden until the first activation, placed in DOM order
directly after the bar row so the announcement reads in natural order; the row's
`aria-describedby` names it. The row keeps `aria-disabled="true"` (not the `disabled` attribute —
a `disabled` button swallows focus and the click that reveals the reason) and never disappears
from the list.

**Hand-off is top-level navigation, never a subresource fetch.** Opening an admin session =
navigating a **new top-level browsing context** to the admin URL (`<a target="_blank">` anchor
default or `window.open`). A `fetch` of the admin URL from the hub origin — even with `mode:
"no-cors"` — is a security bug: it puts a cross-origin request on a URL that can carry project
context, the response bytes can be read on same-scheme redirects and re-enter the hub DOM, and it
lets the admin server set cookies through the hub's request path. The tests assert the
navigation-vs-fetch boundary structurally (§7), not only by spy.

## 3. Disabled states and reasons — verbatim, single precedence chain

One resolver (`adminReason` / `devButton` in claude.js) computes the reason by this precedence;
first match wins; tests assert the **exact strings** character-for-character (a2a §7 is the
source; `a2a-design.md` l.725-751):

1. no valid `admin_origin` stored → `Needs the admin origin: A1 phase 2` (also the title on the
   footer link and the reason on the admin row)
2. launcher state pending (first poll not back) → `Checking the launcher…`
3. launcher up but `project_admin` false → `Project admin is off on this launcher`
4. project admin on but the selected project not in `admin_projects` → `Not in broker.json`
5. claude capability missing → `Claude Code not enabled on this launcher` (a2a §7, verbatim,
   already implemented — kept in the chain so precedence order is testable end to end)

Stale-state decoration: while `state.launcherStale` (a previously good poll followed by an
error), the launcher pill stays and an extra note reads exactly
`Launcher status erroring — last known state`; it rides the same channel as
`#launcher-refresh-note`'s error text and does **not** change a button's enabled state.

## 4. Button state table (tests follow this row by row)

| control | enabled iff | disabled reason (title / aria-describedby) |
|---|---|---|
| `#chat-claude-new` | `state.launcher?.claude && state.launcher?.claude_ui` | precedence §3.2/§3.3 then `Claude Code not enabled on this launcher` (exact copy already in claude.js, unchanged) |
| `#chat-admin` (row) | valid origin (§5.4) ∧ `launcher.project_admin === true` ∧ selected project ∈ `admin_projects` | §3.1 / §3.3 / §3.4, rendered into `#chat-admin-reason` (§2) |
| footer `Admin page →` | valid origin | §3.1 |
| admin row (offline host) | — | rendered, `aria-disabled="true"`, reason text from the host row's `error`/`reachable` state (row disabled ⇒ click reveals reason, same channel) |

`state.launcher === null` (pending) renders controls in their pending/disabled-with-reason form but
never removes the admin row or the bar controls; a row whose *host* is unreachable renders disabled
with its reason — the row never disappears.

## 5. DOM and rendering contract (textContent only)

Every dynamic string — project titles, session labels, host labels, reasons, deadline text — is
written with `textContent` (or `document.createTextNode`). The only attributes this step builds
are `href` (validated origin only), `title` (reasons), `aria-*`, and `dataset.session` (existing
pattern). No `innerHTML`, no template-string assignment to `outerHTML`, no `insertAdjacentHTML`,
no inline handler attributes (`onclick="…"` strings are banned; the source guard tests for them).

### 5.1 Where the pieces live
The picker stays in `views/sessions.js` (it is project-session UI); `views/claude.js` keeps
ownership of its start button via a render-target query at `#chat-claude-new`; launcher state is
read from `state.launcher` — no second poller. `views/running.js` (l.49-60, 267-280) owns the
poll; step 7 only reads its state. The admin row is **state-dependent**: an `<a id="chat-admin">`
when eligible, a `<button id="chat-admin" aria-disabled="true">` when not (one id, two forms — the
tests match on the form the state demands).

### 5.2 Row anatomy (one row per admin host; here: one host)
```
.picker-row
  .session-row (span)            label: textContent only
    · display label: `label.trim() ? `${label.trim()} (${host})` : "(unnamed host)"`,
      host = new URL(origin).hostname, empty host → `#${i}` (0-based index + 1, stable while
      row order is); title only for truncation
    · running chip (§8)
  #chat-admin (a.chat-admin | button.chat-admin)   "New admin session"
```
`aria-disabled="true"` + `aria-describedby="chat-admin-reason"` on the button form (no
`aria-expanded` — the row expands nothing; the reason line is its described-by target); the anchor
form carries `href`+`target="_blank"`+`rel="noopener noreferrer"` and no `aria-disabled`. The
button's activation shows the §3 precedence reason in the bar-level line (§2) and never touches
the dropdown's open state. Ineligible rows are never removed from the list.

### 5.3 Dropdown order (ruling 24, literal)
1. `All projects` + project option rows (existing behaviour, `session-picker` options unchanged);
2. `.picker-sep`, then the New OpenCode row — kept as the row with the existing copy
   `New session in <project>` plus `title="New OpenCode session"` (the ruling's phrase as the
   accessible name; the visible copy stays because the a2a-4 i18n test pins the source text);
3. `.picker-sep`, then the admin rows per host row (in `/api/hosts` order);
4. `.picker-sep`, then the footer link `Admin page →` (same builder, §5.4, `agent=claude`).
Close on: outside click (the `CLICK_AWAY_EXEMPT` set, §1), project switch, Escape (focus returns to
the control). Opening never changes the current view; no `showView` call on any picker path.

### 5.4 The one origin validator and the one builder (shared)
`validateAdminOrigin(value) -> URL | null` in `views/sessions.js` (exported; pure): parse with
`new URL`, reject on throw, then require `protocol === "https:"`, empty `username`/`password`,
empty `search`/`hash`, `pathname` ∈ {`""`, `"/"`}; non-empty port allowed.
`adminOriginFrom(state)` = first host row (in `/api/hosts` order) whose `admin_origin` validates,
else null. `app.js renderAdminLink` (l.147-154) switches to importing this validator — same
behaviour, one rule in one place. The hand-off URL builder:
`handoffHref(origin, project, agent)` constructs `new URL(origin)`, then
`u.searchParams.set("project", project); u.searchParams.set("agent", agent); return u.toString()`.
`URLSearchParams.set` performs the single encoding (`alpha beta` → `alpha+beta`, `%` → `%25` —
never a manual `encodeURIComponent` on top, which would double-encode); the URL object guarantees
no `/admin/` path prefix is added. Tests assert the exact returned string and the decode round-trip.

### 5.5 The hand-off path (security spine)
`openAdminUrl(project, origin)` (sessions.js) = `handoffHref(origin, project, "claude")` then
`window.open(url, "_blank", "noopener")`; an invalid origin makes `handoffHref` throw and the
caller shows §3.1 instead. There is exactly one call site of `window.open` in the step's diff and
no fetch/XHR/iframe/form anywhere near it (§7 guard). The anchor form means plain click and
keyboard Enter both take the browser default; a keydown guard adds Space (buttons get it free —
the anchor form needs it explicitly: `keydown` `" "` → `preventDefault` + the same
`openAdminUrl` path, keeping "exactly one hand-off per activation").

### 5.6 The bar buttons
`#chat-project`: keeps id/`aria-controls`/`aria-haspopup`, `aria-expanded` maintained; label is
the same source the `#chat-project-filter` sync line uses. `#chat-claude-new`: claude.js's
`devButton("claude-start", …)` renders into the bar instead of the launch section; state rules
unchanged (§4); `claudeSignature` gains the two launcher booleans so memoization stays honest;
the dispatch selector (claude.js l.723) widens from `#session-picker [data-claude]` to match the
bar button too, and the `#claude-modes` listener (l.735) is untouched.

### 5.7 Launching Claude (behaviour unchanged)
The same dispatch as before — ruling 24 changes where the button lives, not what it does. The
"Starting…"/disabled rule and the broker/permission_modes logic stay byte-identical in behaviour;
the step's tests re-assert the disabled states only (a2a §7's copy is already pinned elsewhere).

### 5.8 Stop + the 4 s deadline
Per a2a §7: stop = `POST /api/hosts/<id>/launcher/sessions/<sid>/stop` with the launcher command
body `{action: "command", cmd: "stop", target: "admin", project: <row project>}` (+ the token
field the existing wrapper adds). The UI's stop path in `running.js` (l.188-210) is the idiom to
follow: raw `fetch`, note text from the body's **`detail`** (there is no `message` field),
`STOP_CONFIRM_MS = 4000` and `fmtDeadline` live module-private in running.js (l.18, l.39) —
import them or copy them in, never reach across the module. Deadline text after a 2xx:
`Stopping… <fmtDeadline(Date.now() + STOP_CONFIRM_MS)>`; failure note:
`Stop reported a problem: <detail>`. The a2p UI never posts the hub's own proxy as a *session
URL derived from headers* — the URL is built from `(host id, session id)` path segments only
(host-trap §12).

### 5.9 Running chip and footer
`Running N` / `No running session`, N counting rendered rows whose session status ∈
`{starting, streaming, retrying}` (the existing status vocabulary). Footer:
`Admin page →`, `rel="noopener noreferrer"` (build via `relList.add` twice — order-independent,
no exact-string equality on `rel`), href from the same builder; hidden entirely when
`adminOriginFrom` is null (no dead link).

## 6. Event wiring; which pinned tests move with this step

All handlers attach once at module init on stable ids (`#chat-project`, `#chat-admin`,
`#chat-admin-reason`, `#session-picker` delegation); row content rebuilds freely without
re-attaching. The document click-away handler grows only the `CLICK_AWAY_EXEMPT` constant (§1).

Pinned tests that **must be re-pinned in the same commit** that changes their target (re-pin,
never delete, behaviour never relaxed):
- `hub/tests/test_ui.py` `TestSessionPickerInSource` (l.1241-1344) — the setAttribute whitelist,
  the `.textContent =` RHS whitelist, the `item.title` count, the panel shell identity, and the
  `.chat-project`/`.session-picker` geometry pins move with the markup; the whitelists **grow by
  exactly the new allowed forms** (list in a2p-1 §6), the guards themselves stay.
- `hub/tests/test_sessions_ui.py` — the source pins that name the old panel shape re-pin to the
  new markup, same copy.
`test_c1a1_browser.py`'s `open_picker` (l.596-610) already clicks `#chat-project` — zero edits;
`test_c1a1_ui.py` source pins must keep passing as-is. `test_anonymity.py` hashes every token in
`docs/` — this file uses only `example.com` / `127.0.0.1` / `localhost` forms, and so must the
specs.

## 7. The security spine a2p-2 tests (all real-browser, all green)

1. **No-fetch proof**: activate an eligible admin row against a `FakeLauncher` that counts
   requests; zero requests hit the hub or a mock admin server; `window.location.href` unchanged;
   a monkeypatched `window.fetch` is never called during activation; source scan of sessions.js
   shows no `fetch(`/`XMLHttpRequest`/`iframe`/`<form`/`submit(` on the hand-off path (the scan
   covers the whole file — there are no legitimate uses to except).
2. **Anchor contract**: eligible form is `<a>` with `target="_blank"`, `rel` token-set ⊇
   `{noopener, noreferrer}` asserted via `relList.contains` (never exact string equality — token
   order is not contractual), `href` exactly per §5.4 incl. a space project name and a `%`
   project name (single encoding both times).
3. **Origin source**: a decoy `window.hubConfig.admin_origin` (if code ever re-reads it) is
   ignored; the hand-off URL equals the host row's `admin_origin` value; a host row whose
   `admin_origin` is `javascript:alert(1)`, `http://admin.example.net`, `https://u:p@admin.example.net/`, `https://admin.example.net/y`, or
   malformed never produces a launchable href and the row survives (disabled, reason shown).
4. **Body scope**: the stop request body is exactly the launcher's stop command doc for the
   clicked row's project — `target: "admin"`, `project` set — and contains nothing header-derived
   (no URL, no origin string) — FakeLauncher records it.

## 8. State matrix (every state tested, none optional)

| state | bar | dropdown open | admin row | reason line |
|---|---|---|---|---|
| launcher pending (`state.launcher === null`) | both controls present, Claude disabled `Checking the launcher…` | rows render | anchor-or-button per origin validity | available |
| launcher good, admin off | normal | renders | button `aria-disabled`, reason §3.3 | on activation |
| admin on, project not brokered | normal | renders | button, §3.4 | on activation |
| eligible | normal | renders | anchor href | hidden |
| valid origin, first poll pending | normal | renders | button, §3.2 | on activation |
| no valid origin | Claude disabled §3.1 | renders | button, §3.1, hidden footer | on activation |
| stale poll (`launcherStale`) | pill keeps last state + note | renders per last known | unchanged | stale note appended to reason |
| host offline | — | renders | disabled row + row-level reason | — |
| zero projects | control label `All projects` | empty-list message only | footer only (valid origin) | — |

Empty, pending, error and populated states each get a named test in a2p-1/a2p-2's modules.

## 9. Accessibility contract (ruling 24 makes the control a combobox-ish toggle — keep it simple)

`#chat-project` is a `button` with `aria-haspopup="listbox"` and truthful `aria-expanded`; the
panel keeps `role="listbox"` + `aria-labelledby` pointing at the control (unchanged base
behaviour). The row/option markup and keyboard model keep the base's rules: arrows move the
active option, Enter activates, Escape closes and focuses the control, focus on open goes to the
first enabled row, Tab cycles within the open panel and closes it afterwards. The admin button
form must be reachable and its `aria-describedby` target visible when shown. `#chat-admin-reason`
carries `role="status"` (polite live region) and is the `aria-describedby` target of every
ineligible admin control. Ineligible-row activation keeps focus where it is and does not move
focus out of (or into) the panel — the reason appears in the bar line that follows the controls in
DOM order (§2). Live proof in a2p-3 (`aria-expanded` flips, focus movement, a11y tree role of the
control). Contrast: only existing app.css tokens used (§10).

## 10. CSS contract table (the only styling freedom this step takes)

| selector (base) | may change | must keep verbatim |
|---|---|---|
| `.chat-project` (height 32 px, font 13 px, border-bottom rule; test_ui l.1327-1333 pinned) | additive rules only under a widened selector | all pinned tokens |
| `.session-picker` geometry (l.1318-1326) | additive (max-height under viewport pressure only) | width/left/border/padding tokens |
| `.session-picker::-webkit-scrollbar` (app.css l.342) | untouched | untouched |
| `.picker-row`, `.session-row`, `.picker-sep` | untouched | untouched |
| new `.chat-bar`, `.chat-admin`, `.picker-note#chat-admin-reason` | free — tokens only | `:focus-visible` outline present; `prefers-reduced-motion` collapses transitions |

New classes may *extend* the base selectors (`.chat-project.chat-admin` is illegal — the admin
row is its own class `.chat-admin`); replacing `.chat-project`/`.session-picker` rules is out of
scope: the geometry pins in `test_ui.py` fail, and that is the guard doing its job. Light/dark
need no new rules: everything below the bar inherits the existing token scheme; the only explicit
colours allowed are existing `var()` names. The §11 screenshot pair is the proof.

## 11. Screenshot matrix (ruling 25 — owner-acceptance artefacts)

Eight PNGs, 390×800 and 1440×900, light and dark, dropdown closed and open, exact names
`390x800-light-closed.png` … `1440x900-dark-open.png`, written under
`${DELEGATE_EVIDENCE_DIR:-/tmp}/a2p-shots/`. A missing PNG **fails** the suite (ruling 25: no
skip-if-absent). The captures come from `test_a2p_shots.py` via the repo's existing CDP helper
(`test_c1a1_browser.PageSession`), scheme forced with `Emulation.setEmulatedMedia`; the step's
verify command additionally checks all eight files exist on disk after the run. Layout assertions
that the screenshots must visually satisfy: no control overflows the 390 viewport; the dropdown
opens below the control and never covers it; identical rects in light and dark; the reason line
reserves no layout when hidden (`hidden`, not `visibility`).

## 12. Hostile / degenerate data traps (the suite must cover all)

- a host row with `admin_origin: "<img src=x onerror=alert(1)>"` → invalid, row survives;
- a project title of 10 000 chars incl. U+202E (RTL override) and `<script>` text → clipped by
  CSS, textContent round-trips exactly, no element created from it;
- `admin_projects: ["alpha", null, 42]` → non-string entries ignored (never truthy-compared);
- `label: 12345` → label falls back to `(unnamed host)` via an explicit `typeof` check, never
  `[object Object]`-style coercion;
- two host rows sharing one `admin_origin` → two rows, stable order, no key collision;
- a host row `reachable: false` with valid origin → disabled row, reason shown, footer link
  still enabled (footer keys on origin only);
- `/api/hosts` fetch error → same render as pending (never removes rows already rendered);
- every test that scripts these runs in the real browser, asserts no dialog fired (`window.onerror`
  trap installed) and the DOM still matches the expected shape afterwards.

## Owner questions (answered — picked option recorded with rationale)

1. **Does the New-Claude button itself carry the broker/project reason, or only the dropdown's
   admin row?** Decision: the **bar button** carries §3.1 (its copy exists there since a2a — "the
   Claude start button explains why it is off"), the **admin row** carries the project-scoped
   reasons §3.3/§3.4 in the bar-level line, and the hand-off URL always opens
   `?agent=claude` regardless of which control launched (the admin page's own mode selector then
   owns the choice). Rationale: one precedence chain, no duplicated copy, the ruling 9 wording
   ("New Claude session") preserved.
2. **The ruling's "New OpenCode session" as visible copy vs the pinned a2a-4 source text.**
   Decision: keep the existing visible copy (`New session in <project>`) and the ruling's phrase
   as the `title`/accessible name; renaming visible copy is A2 step 8's if the owner wants it.
3. **Step 6's absence in this base.** Decision: tests script `project_admin`/`admin_projects`
   via `FakeLauncher` (the a2a-3 pattern) so this UI is green before and after step 6 lands; a2p-2's
   stop-body test names the step-6 relay as the field's real producer.

## Risks

The one live risk is silent drift between this design and step 6's real field shapes once
`a2a-3`/`a2a-4` land on this branch; the defensive render + scripted tests make drift a UI-no-op,
and the §6 re-pin list is the contract the next slice diffs against.
