# A2P — the unified picker: design for slice step 7

Status: ready for chain. Base: `a2-steps-6-8` at `4c60732`. Three steps, chain plan in
`a2p-chain.json`. UI only: no daemon, launcher, hub-route or config change — the endpoints,
options fields and sessions rows this slice consumes are the A2a hub's job (its step 6, per
`a2a-design.md` §4/§7) and already specced there.

## 1. What step 7 is

The A2 design (`a2-design.md` §5.2, §7, ruling 24) puts a session picker in the chat header.
Ruling 24 overrides its exact widget layout:

> **Ruling 24 (owner, 2026-11-19).** The bar carries, on top, two buttons: **New Claude session**
> and **New admin session**. The session dropdown — the list of running/paused sessions, OpenCode
> and admin alike — opens only on demand from its own control, never as a side effect of selecting
> a project, and closes on project switch. "New OpenCode session" lives in the dropdown, not on
> the bar. Commit `6eed48f` already makes project selection close the picker; keep that behaviour.

The current picker is the H2c one (`hub/static/views/sessions.js`): a slim bar `#chat-project`
over the chat frame that opens `#session-picker` with the project's OpenCode sessions plus the
C1+A1 Claude section. A2P adds to it — and only it:

1. the second bar button (admin), with everything rulings 25/26 say about its states;
2. the admin session row inside the dropdown (state, deadline, Stop);
3. the launcher-status consumption the bar needs to show all that, riding the poll `running.js`
   already owns (`state.launcher`);
4. the copy table (§5), the a11y story (§6), the visual story (§7), and the tests (§8).

What A2P **does not** add: hub routes; `options.project_admin`/`admin_projects`/`admin_members`
(A2a step 6 sends them; here they are read defensively and every test fakes them); any start or
extend call (a2a §7: nothing on the hub origin starts or extends an admin session — the hand-off
is a link); and any change to the project list's selection semantics (6eed48f is law).

## 2. The bar

Real elements, no `role=button`. Order on wide screens: project control, **New Claude session**,
session-dropdown control, **New admin session**. The dropdown control is the existing
`#chat-project` — it already is "its own control" (a click toggles; a project selection closes,
per 6eed48f), it already carries `aria-expanded`/`aria-controls`, and reusing it keeps every
focus test in `test_sessions_ui.py` honest. The two new controls are `<button type="button">`s
inside the bar, styled `.claude-btn`-kin; "New Claude session" moves up from the panel's Claude
section (the section then shows the session's state/terminal/stop rows, and the mode select rides
beside the bar button only when the launcher sends `permission_modes`).

Narrow (≤ 640 px, the existing media-query breakpoint): the bar becomes
`[▾ control] [Claude] [Admin]` — labels shorten to exactly `Claude` and `Admin`; the dropdown
control keeps its caret plus the project label (which ellipsizes), and the full strings move to
each control's accessible name: `.textContent` shortening must never shorten an `aria-label`.
Four 44 px-tall tap targets fit 390 px because the short labels are ≤ 6 characters and the caret
control flexes and ellipsizes (`min-width: 0`, the existing pattern).

Both new buttons are **present and enabled only in the states §3 says**; disabled ≠ removed: a
disabled control carries `aria-disabled="true"`, stays focusable, and its reason is reachable
programmatically (§6 fixes the mechanism and why).

## 3. State model and data reads

All reads are defensive — a field that A2a step 6 does not send yet must not throw: the options
object is read as `const o = (launcherAnswer && launcherAnswer.options) || {}` and every a2a
field is `=== true` / array-checked. Sources:

| Shown | Read from | Timing |
|---|---|---|
| the admin button's enable/disable | the `/api/hosts` row `admin_origin` for the selected project's site (today's field, the one `renderAdminLink` uses, on `state.hosts`) **and** `options.project_admin` from the launcher status options | on render; hosts ride the existing hosts poll |
| the hand-off link origin | same `admin_origin`, re-validated at every paint (§4) | on render |
| "Not in broker.json" | `options.admin_projects` — the selected project's name absent from the array | on render |
| the admin session row (state, deadline, `rc_name`, `link`, `member`) | `sessions[]` entries with `target === "admin" && project === <selected project name>` in `state.launcher` (the whole last `/api/launcher/status` answer, published by `running.js`'s `publish()`) | the existing 10 s poll while the document is visible — A2 §7's "poll while a row shows a deadline" is already that poll; A2P must not add a second one. Opening the dropdown triggers one immediate `running.refresh()` (the pattern claude.js's stop already uses) so an open never paints a stale deadline |
| status unavailable / erroring | `state.launcher === null` after a poll (running.js's rule: a 503 or a bad answer publishes null) → row shows `Status unavailable`, Stop stays visible | same |

`state.launcher.options.dev` keeps gating the Claude bar button exactly as `claudeAvailable`
gates the section today (root host + `launcher: true` + dev option + under-root). When it is
false the button is **hidden**, as the section is today — hiding a control for a capability the
deployment does not have is not the same as disabling one (ruling 25/26's disabled-with-reason
contract is about configured *but off or missing here*).

The picker's repaint rides the existing `lastSignature` guard: the signature gains the admin
fields that show (row state word, deadline minute, disabled reason, status-null flag), so the
poll repaints the row and nothing else, exactly like the Claude section does today.

## 4. The admin hand-off (the hard rule)

"New admin session" performs a **top-level navigation**: a real `<a rel="noopener">` in the bar,
whose `href` is set only from a validated origin (the same shape as app.js's `#admin-link` and
a2a-9's `#a2h-admin-link`). The anchor *is* the control: anchors are natively activatable by
mouse and Enter, which is why no `div[role=button]` and no separate button wrapper exists.
Never a fetch, never a POST, never an iframe: the admin session is started on the admin page, by
its own Open click — a GET never starts anything (a2a §7).

The URL is exactly `admin_origin + "/?project=" + encodeURIComponent(project)`. `agent` is not
in the link: the admin page reads `agent` only when present (a2a-9), so omitting it lets that
page offer both agents with the launcher's own `options.agents` order as the default. §9-1 asks
the owner whether the bar should pre-pick Claude; the picked answer is no.

Origin validation before any href is written (`adminHandoffUrl(origin, project) -> string|null`,
a pure exported function so the unit table can pin it): parse with `new URL()` inside try/catch —
a throw means unusable; require `u.protocol === "https:"`, pathname `""` or `"/"`, empty
`search`, `hash`, `username`, `password`, and `u.origin` not `"null"`. Anything else is unusable.
Unusable ⇒ no href and the control renders disabled with the reason
"Needs the admin origin: A1 phase 2" — ruling 26's copy for a *missing* origin is reused for a
*malformed* one, because from the page's seat both mean the same thing: the hub does not know a
safe admin origin. (The distinction belongs to `hub doctor`, not to a user.)

The same function guards the anchor against a mid-session config change: the hosts poll may
replace `admin_origin` between paints; the href is rewritten from the validated value on every
render, and a value that stops validating gets `removeAttribute("href")` plus the disabled
treatment rather than pointing anywhere stale.

## 5. Copy — exact strings (pinned by tests; no test may reword them)

| Where | String |
|---|---|
| bar button | `New Claude session` / narrow: `Claude` |
| bar control | `New admin session` / narrow: `Admin` |
| dropdown control accessible name | `Sessions for {project}` (aria-label; the visible label is the project name as today) |
| dropdown item | `New OpenCode session` (replaces today's `New session in {label}` — the bar already names the project) |
| admin section head | `Project admin` |
| admin row states | `Starting…` / `Running` / `Waiting for you` / `Stopped unexpectedly`; deadline rendered beside the running word as `until {HH:MM}` (local, 24-h, from epoch **seconds**); untimed: `No time limit` |
| Stop button | `Stop` → second click `Really stop?` (4 s revert; same pattern and constant as claude.js / running.js) |
| status unavailable | `Status unavailable` |
| empty list | `No sessions yet` (shortened from today's `No sessions yet in this folder`; step 1 changes both the constant and its pinned test) |
| loading | `Loading sessions…` (existing) |
| disabled — project_admin off | `Project admin is off: enable project_admin in admin.json` |
| disabled — project not brokered | `Not in broker.json` |
| disabled — no/unsafe origin | `Needs the admin origin: A1 phase 2` |

Server-originated text (`admin_projects` names, member names, `rc_name`, OpenCode titles) reaches
the DOM only as `textContent`. The only attribute a server string can reach is the validated
hand-off href built by `adminHandoffUrl`, and the only other attributes remain today's four.

## 6. Accessibility

* Real `<button>` / `<a>` elements everywhere; Tab order = bar left-to-right, then panel
  top-to-bottom. Enter/Space activate (Space activates focused buttons natively; Enter the
  anchor). ArrowUp, ArrowDown, Home and End roving inside the panel grows to cover the admin row's
  Stop control; Escape closes and returns focus to the control that opened the dropdown
  (`#chat-project`) — 6eed48f's contract, unchanged, because neither bar button opens the
  dropdown at all.
* Click-away still closes; the exempt list grows by the two bar controls' ids, so a click on a
  bar control is its own action and never a stray close.
* The disabled reason is reachable two ways, deliberately: `aria-disabled="true"` + `title`
  (pointer users), and the same sentence rendered as a visible `.picker-note` line in the
  dropdown's admin section (touch and screen-reader users — a `title` is unreachable on touch).
  The visible note is the authoritative one; `aria-describedby` is *not* used because the note
  already sits in place order right after the control's section head, and a second mechanism
  would be one more thing to drift. (This is the §2 choice.)
* The two-click Stop announces: the button's own label flips to `Really stop?` — a visible and
  accessible-name change, matching running.js and claude.js exactly; revert timer 4000 ms like
  both siblings.

## 7. Visual

Existing tokens only: `--bg --panel --line --ink --muted-ink --accent --danger --ok --warn
--touch`. No new dependencies, no icon fonts (the caret stays the existing text glyph). New rules
go beside `.claude-btn` / `.session-row`, same family: `.bar-action` (the two bar controls: the
32 px slim look on wide, `min-height: var(--touch)` on touch), `.picker-admin-row` (state word +
a `.claude-dot`-kin state dot), `.picker-note.is-reason` (the disabled sentence). Dark mode needs
zero new variables: every colour above already flips in the `prefers-color-scheme: dark` block.
The panel keeps its pinned geometry (`position: absolute`, `max-width: 560px`, `max-height: 60%`,
`overflow-y: auto`) — a new admin row cannot make the dropdown grow past that; the list scrolls,
which is why the empty and loading states are rows and not panel resizes.

At 390×800 nothing scrolls horizontally: short labels (§2), the admin row's actions sit right in
flow (never absolute), long titles ellipsize, the row may wrap to two lines. At 1440×900 the bar
shows the full labels and the dropdown keeps its 560 px column.

## 8. Tests (the acceptance surface; per-step detail in the step specs)

* **Unit (no browser, step 2's module):** `adminHandoffUrl` table — https root only accepted;
  rejects `http:`, `https://admin.example.com/door`, `?x`, `#frag`, `user:pass@`, garbage, empty,
  non-string. Project-name encoding: `a b`→`a%20b`, `a&b`→`a%26b`, `é`→`%C3%A9`, `a/b`→`a%2Fb`,
  `a?b`→`a%3Fb`, `#`→`%23`; U+202E passes through raw (the admin page's problem, the URL is not
  the injection point); a 10 000-char name is not capped by the UI (encodeURIComponent output).
* **Browser:** ruling-24 open/close contract (step 1, `test_sessions_ui.py`); each of the seven
  states §3/§5 lists gets its own test (step 2, new `test_a2p_admin_browser.py`), driven by a
  scripted launcher world (the C1A1 `_world_answer` pattern: the fake's status answer carries
  `options.project_admin`/`admin_projects`/`admin_members` and an `admin` sessions row, so the
  a2a step-6 fields are faked without touching the hub); plus a hostile test: a project literally
  named `<img src=x onerror=alert(1)>`, `rc_name`/member names with U+202E, and a 10 000-char
  OpenCode title → nothing parses as markup, no navigation happens, the row ellipsizes, and the
  raw strings still read back through `window.__{project}.getState()`.
* **Static (`test_ui.py::TestSessionPickerInSource`, updated in step 1's own scope):** the
  setAttribute allowlist grows by `title` only; `href` stays forbidden via setAttribute and is
  pinned as a property assignment guarded by `adminHandoffUrl`; no markup strings; the copy
  table's strings pinned exactly; CSS geometry tokens stay as today.
* **Screenshots are acceptance evidence (step 3):** a browser test saves eight PNGs into
  `${DELEGATE_EVIDENCE_DIR:-/tmp}/a2p-shots/`, named
  `<w>x<h>-<light|dark>-<closed|open>.png`, at 390×800 and 1440×900, light and dark, with the
  populated fixture (three OpenCode sessions incl. an em-dash title, a running admin session
  showing `until HH:MM` and Stop). Step 3's verify greps the module's `ok` line **and** counts
  the eight files, so a missing chromium fails the step instead of skipping it.

## 9. Owner questions (each with the picked option — reverse one before the chain runs and the
## step specs follow)

1. **Does "New admin session" open Claude directly, or offer Claude/OpenCode?** Picked: **one
   button, no pre-pick** — the hand-off carries only `?project=` and the admin page offers both
   agents (a2a-9 already honours an optional `agent` param, and the launcher's `options.agents`
   order is the default). A split button or a two-item menu would add a decision layer ruling 24
   does not ask for; it says two buttons on top, not three controls. Cost of changing: the bar
   becomes a two-item menu (new open/close state), `adminHandoffUrl` grows an `agent` argument,
   one browser test, one screenshot fixture.
2. **Does the bar itself show the admin session's state dot while the dropdown is closed?**
   Picked: **no** — the dot lives in the dropdown's admin row; the bar stays two buttons + the
   caret control. Ruling 26's "dot" reads naturally as the row's dot (claude.js has exactly that
   pattern), and a bar dot would imply polling for a glance nobody asked for while the dropdown is
   ruling 24's on-demand surface. If the owner wants it, it is a one-line CSS copy plus two
   tokens in the bar's signature — the 10 s poll already covers it.
3. **`No sessions yet` replaces today's `No sessions yet in this folder`.** Picked: shorten it —
   the bar names the project, and the longer string does not fit the 390 px panel headroom
   beside the new admin section. One constant plus its pinned test, in step 1.

## 10. Host traps (every step inherits these)

* The host umask is 002 and `XDG_CONFIG_HOME` is exported: tests write their own config dirs
  under tmp with explicit modes (`httputil.write_config` already does); nothing reads `~`.
* Workers never run history-changing git (no commit/checkout/merge/rebase/stash); the harness
  commits per round. Read-only git is fine and encouraged.
* `hub/tests/test_anonymity.py` scans tracked files: no real site values in specs, code, test
  fixtures or copy (example.com-style placeholders only; `admin.example.com` is already the
  harness's stand-in, `browser_front.py`).
* The launcher status fields this UI consumes are A2a step 6's; on this base they are absent.
  Code must not crash without them, and tests fake the whole status answer — do not wait for
  step 6, and do not add hub-side options here (out of scope; it would fight A2a's step 6).
* `deadline` is epoch **seconds** (launcher `_status_view`, mirrored by running.js's
  `fmtDeadline`); rendering it as milliseconds is the classic slip — the tests pin the HH:MM.
* New test modules use free ports (`httputil.free_port()`); the parallel runner runs modules
  side by side.
* Long suites run detached (`setsid -f`), never as SIGINT-ignoring background jobs (AGENTS.md).

## 11. Step map

| Step | Spec | Hard | Gate |
|---|---|---|---|
| 1 | `a2p-1-bar-dropdown.md` — ruling-24 bar, copy, CSS, pinned-test updates | no (no URLs, no new server strings rendered: it re-renders today's) | step modules + scope guard |
| 2 | `a2p-2-admin-handoff.md` — hand-off URL, admin row, Stop, every state, hostile test | **yes** (builds URLs, renders server strings) | **full gate** + shape greps + scope guard |
| 3 | `a2p-3-a11y-screenshots.md` — keyboard/aria audit + the eight acceptance PNGs | **yes** (last step of the chain) | **full gate** both suites + scope guard |

Ordering is load-bearing: step 2 renders inside step 1's containers, and step 3 photographs what
steps 1–2 built.
