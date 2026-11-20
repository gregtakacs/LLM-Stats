# A2 step 7 (picker): the unified picker — slice design

Slice `a2p`. Base branch `a2-steps-6-8` (commit `4c60732`). Three steps, all hub frontend:
`a2p-1-picker-bar`, `a2p-2-dropdown-handoff`, `a2p-3-browser-acceptance`. No server, daemon or
launcher code changes in this slice. Its server-side inputs — step 5's per-project status entries
and options, step 6's project admin model, the admin page's `?project=&agent=` hand-off receiver
(a2a-9) — are pinned by `docs/specs/a2h-4-picker-life.md`, `docs/specs/a2h-design.md` §7 and
`docs/specs/a2a-9-admin-page.md`; **this chain runs after those chains merge** (the base carries
their specs, not yet all their code: `/api/oc-projects` routes exist, `admin_projects`-shaped
options do not). Where a field is not on the base yet, the step specs consume the contract the
named spec pins, not today's payload.

## 1. What the bar becomes

Ruling 24, word for word: the bar top is **New Claude session** + **New admin session**; the
session dropdown opens **only on demand from its own control**, never as a side effect of project
select (the behaviour commit `6eed48f` pinned: the project-select handler sets `pickerOpen:false`;
that line stays), and the dropdown is closed on project switch. **New OpenCode session** lives in
the dropdown.

Concretely, `#chat-project` (today one button with a `Chat <project>` label and a caret,
`hub/static/index.html:56`) becomes a container with exactly two controls:

```html
<div id="chat-project" class="chat-project" hidden>
  <button id="picker-new-claude" class="picker-btn" type="button">New Claude session</button>
  <button id="picker-toggle" class="picker-btn" type="button"
          aria-expanded="false" aria-controls="session-picker">New admin session
          <span class="chat-project-caret" aria-hidden="true">▾</span></button>
</div>
```

- **`New Claude session`** is the one-click hand-off for the current project (§4). Its label is
  the verbatim copy; the element never renders server strings.
- **`New admin session`** is the dropdown's own control (ruling 24's "its own control"): click,
  Enter or Space toggles `#session-picker`; it carries `aria-expanded`/`aria-controls`. A second
  caret toggle would duplicate it; one control, one label, no ambiguity about which button opens
  the list. The old `Chat <project>` bar label moves into the dropdown header (§3).
- The bar keeps its 32px height, `--panel`/`--line` tokens and hidden-until-signed-in-with-a-project
  behaviour (`BAR_HIDDEN` stays pinned). `hub/static/views/claude.js` is not touched — its dev
  section is the admin view's own UI and A2d moves it later (ruling 25).

## 2. Bar states and disabled reasons

One table decides both buttons. Sources: `options` from `GET /api/launcher/status`
(step 6: `project_admin`, `dev`, …), the selected project, `admin_projects`, and the validated
admin origin (§4). `P` = the current chat project.

| Condition | New Claude session | New admin session (toggle) |
| --- | --- | --- |
| bar visible, `P ∈ admin_projects`, `options.project_admin`, valid origin | enabled (navigates) | enabled (opens dropdown) |
| `P ∉ admin_projects` | disabled, reason `Not in broker.json` | enabled |
| `options.project_admin` not true | disabled, reason `Claude sessions are managed from the admin page.` | enabled |
| no host row carries a usable `admin_origin` (§4) | disabled, reason `Needs the admin origin: A1 phase 2` | enabled |
| launcher status still loading | enabled only if the cached status/options allow it; otherwise disabled with no reason line (transient) | enabled |
| launcher status failed/unreachable | unaffected (hand-off is a link, not a launcher call) | unaffected; the dropdown's Claude section carries the state (§3) |

Disabled means `aria-disabled="true"` (element stays focusable and Tab-reachable — a native
`disabled` button leaves the tab order and the reason becomes undiscoverable), the verbatim reason
in `title`, **and** the same reason as visible text inside the opened dropdown (§3) so the reason
never depends on hover. A click on an `aria-disabled` control does nothing, verified per reason.
All three reason strings and the two bar labels are pinned constants; tests assert them exactly.

## 3. The dropdown (`#session-picker`)

`role="group"`, opened only per §1, closed on: toggle again, Escape (focus returns to the toggle),
click-away (`CLICK_AWAY_EXEMPT` extended to the new ids), and project switch (already pinned).
Sections top to bottom, each rendered with `textContent` only:

1. **Header** — `.picker-project`: `Chat <P>` plus the deadline/state of P's admin session when
   one is live (reuses running.js's state words and deadline text, exported in step 2).
2. **Claude sessions** — `.picker-admin`, header copy `Claude sessions`. Rows `.admin-session-row`,
   one per status entry with `target == "admin"`: agent word, project name, state word, deadline
   text (`timed` ⇒ `left`, else `runs until stopped`), the row's own link opens the session's
   terminal via its `link` (same top-level rule as §4), and a **Stop** button using running.js's
   inline-confirm pattern (`Stop` → `Really stop?`, a re-click within the timer) → `POST
   /api/launcher/stop` with exactly the body running.js's `stopBody()` builds for that entry
   (shared helper, step 2; today `{target:"admin"}`, project-free — `hub/adminapi.py`
   `_validate_stop` rejects extra keys on non-dev targets), signed-in cookie, no step-up, then an
   immediate status refresh. Section states:
   loading → `Claude sessions: loading…`; daemon unreachable → `Claude sessions: launcher unreachable`;
   status request failed → `Claude sessions: unavailable — Retry` with a real Retry button that
   refetches; `project_admin` off → `Claude sessions are managed from the admin page.`; empty →
   `No Claude sessions`.
3. **OpenCode sessions** — `.picker-oc`, header copy `OpenCode sessions`, then the existing
   `.session-row` list and empty/error states of sessions.js unchanged, ending with the button
   `.picker-new-oc` copy `New OpenCode session` — the direct relay-create path stays exactly as
   today (A2e/A3 flip it; DECISIONS).

All server strings (titles, project names, agents, member names, deadline text) land via
`textContent`/attribute assignment — no `innerHTML` anywhere in the picker code (static grep pins
it). Injection is hostile-tested in step 2: a title `<img src=x onerror=alert(1)>`, a title with
U+202E, a 10 000-char title — each must render as text, stay clipped by CSS, and add no element
(`#session-picker img` count stays 0; row computed `text-overflow: ellipsis` + `overflow: hidden`).

## 4. Admin hand-off (the security spine)

`handoffUrl(origin, project, agent)` = `origin.replace(/\/+$/,"") + "/?project=" +
encodeURIComponent(project) + "&agent=" + agent`, `agent ∈ {claude, opencode}`. The project name —
the only user-attested string in the URL — is `encodeURIComponent`-encoded exactly once; tests
assert the raw query the admin origin receives.

`admin_origin` comes from `/api/hosts` rows (app.js already picks the first non-null for the admin
link). It is used **only** when it parses as an absolute URL with scheme `https:`, empty or `/`
path, and no query, fragment or credentials; anything else (including garbage that fails
`new URL`) is treated as absent: §2's disabled state with `Needs the admin origin: A1 phase 2`.
Never a `fetch`, never a POST, never an iframe, never a redirect chain followed in-page.

Navigation is **top-level**: the button handler calls `location.assign(url)` (ruling 24 permits
`<a href>`/`location.assign`). `window.open` and `fetch`/`XMLHttpRequest` inside hand-off code are
grep-forbidden in step 2's verify. Because `location.assign` reuses the same tab it creates no
browsing context and no `opener` reference, so there is no surface for `rel="noopener"` to protect
(the rule's intent — no popup an admin page could script, no background request that could leak
credentials — holds structurally); DECISIONS records this reading. The same-tab hop is safe: the
URL carries no credentials, only the project name.

## 5. Data and refresh

New state.js keys: `launcherStatus {phase, sessions, options, error}`, `pickerProjects` (from
`GET /api/oc-projects`). Fetch both when the bar first shows and on every project switch that
keeps the dropdown closed but marks data stale; re-poll status every 10s while the bar is visible
(same cadence as running.js); opening the dropdown triggers one immediate refresh; Stop refreshes.
The two failure faces are the hub's own (`hub/adminapi.py`: unreachable ⇒ HTTP 503 with body
`error` `launcher_unavailable` ⇒ the Claude section's `launcher unreachable` line; anything else
non-OK ⇒ `unavailable — Retry`), and a request that dies in transit counts as Retry-able too.
One status failure marks the Claude section's error state but changes nothing else. No site values
are stored; `test_anonymity.py` stays green and is in every verify's grep list.

## 6. Visual: 390px, both schemes, existing tokens only

Only existing `app.css` custom properties (`--panel`, `--line`, `--ink`, `--muted-ink`, `--accent`,
`--touch`, …); no new colours, no dependencies, no icon fonts, caret stays the `▾` text glyph.
`.chat-project` becomes a flex row, reusing the bar's existing spacing. The two verbatim labels measure ≈ 2×130px
at the existing 14px/400 button style, so 390px fits after the `Chat <project>` label leaves the
bar (it moves to the dropdown header — that is **how** the labels shorten); below ~360px the
buttons take `min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap` — a
visual-only clip that keeps the full `textContent` and accessible name (tests assert both).
No horizontal scroll at 390×800 (asserted: `documentElement.scrollWidth ≤ innerWidth`). Light and
dark both screenshotted (§8): the picker inherits the scheme purely through the tokens it reuses.

## 7. Accessibility

Every control is a real `<button type="button">` (or reuses one), so Tab order is the DOM order
bar → dropdown top to bottom. The toggle: Enter/Space open and close, ArrowDown moves to the first
row, ArrowUp/ArrowDown walk rows and section buttons, Home/End jump, Escape closes and restores
focus to the toggle, `aria-expanded` mirrors state (already pinned). Dropdown rows are anchors or
buttons, never divs with click handlers. Disabled reasons: `aria-disabled` + `title` + visible
line (§2). The Retry and Stop buttons announce their own labels. Keyboard flow is exercised in
step 3 against the populated fixture.

## 8. Acceptance evidence: screenshots

`hub/tests/test_a2p_browser.py` (step 3) drives the same h2b browser stack with a populated
fixture (two live admin sessions — idle and busy with deadline, three OpenCode sessions incl. one
long title, project selected), and saves exactly eight PNGs named
`<w>x<h>-<light|dark>-<closed|open>.png` (`390x800`, `1440x900` × `light`,`dark` × `closed`,`open`)
into `${DELEGATE_EVIDENCE_DIR:-/tmp}/a2p-shots/` via CDP `Page.captureScreenshot` after
`Emulation.setDeviceMetricsOverride` + `Emulation.setEmulatedMedia` (prefers-color-scheme). The
module **fails, never skips**, without Chrome/CDP and fails if any PNG is missing or under 4 KiB —
screenshots are the acceptance evidence for a UI slice. Step 3's verify re-checks the eight files
from the shell so the orchestrator's container proves it too. The host runs them at 390×800 and
1440x900, light and dark, and reads every PNG (AGENTS, verify-ui.md).

## 9. Slicing

| step | hard | files |
| --- | --- | --- |
| a2p-1-picker-bar | false | index.html, app.css, state.js, app.js, sessions.js (bar/status plumbing, markup, CSS, static+browser state tests); test_ui.py static contract updated |
| a2p-2-dropdown-handoff | true | sessions.js (dropdown contents, admin rows, Stop, hand-off URL, validation), running.js (export helpers); test_sessions_ui.py updated; injection + encoding tests |
| a2p-3-browser-acceptance | true (last) | hub/tests/test_a2p_browser.py (screenshots + keyboard walk; fixes inside step 1–2 files allowed) |

Steps are sequential on one branch; every verify runs the parallel runner, greps its modules `ok`
and forbids `^FAIL `/`^not ok` (a2a-chain style). Host traps (umask 002, exported
`XDG_CONFIG_HOME`, setsid for long suites, free ports) apply to all three.

## Owner questions

1. **Does `New Claude session` go straight to the admin page (chosen: yes — one click, prefilled
   `agent=claude`, owner confirms there), or should it instead offer Claude/OpenCode first?** The
   offering variant belongs to the dropdown, where `New OpenCode session` already lives, so
   straight-to-prefill is the reading implemented; flagging because it is a one-tap commitment.
2. Should `New OpenCode session` also become a hand-off in this slice? Chosen: **no** — it keeps
   today's pinned relay-create path (A2e/A3 owns the flip); it is not part of ruling 24's
   "both go through the admin page" pair.
3. Is same-tab `location.assign` acceptable for the hand-off (chosen: yes, §4), or does the owner
   want a real `<a href>` (which cannot sit disabled-and-focusable cleanly alongside the reason
   states) or a new tab (which re-adds `rel="noopener"` literally but loses chat state)?
4. When `options.project_admin` is off the bar still shows `New Claude session` disabled with
   reason `Claude sessions are managed from the admin page.` — or hide it entirely? Chosen: show
   disabled (reasons beat vanishings), mirroring a2a-9's card behaviour.
