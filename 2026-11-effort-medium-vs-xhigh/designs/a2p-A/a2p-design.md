# A2 phase 2 — the unified picker (a2p): design

Implements `docs/specs/a2-design.md` §5.2 and ruling 24 as one step of slice A2
("the hub UI: a session picker that covers every way in"), and the display and
hand-off contract a2a §7 fixed for it (rulings 24–26). The chain is
`docs/specs/a2p-chain.json`; this file is the overview, each step's spec is the
authority for what it builds.

Read first: `docs/handoff.md`, `docs/specs/a2-design.md` (§5.2, §7, ruling 9,
rulings 24–26 at the end of the file), `docs/specs/a2a-design.md` §7, the step-6
specs `docs/specs/a2a-3-units.md` (the status entry), `docs/specs/a2a-7-hub.md`
(the hub rows and `options.project_admin`) and `docs/specs/a2a-9-admin-page.md`
(the page this picker hands off to); then the current picker
`hub/static/views/sessions.js`, its tests `hub/tests/test_sessions_ui.py`, and
the launcher parts of `hub/static/views/claude.js` and
`hub/static/views/running.js`. The step-6 specs are contract, not code to read:
the picker consumes what they fixed, it does not re-decide it.

## 1. What is built

The chat header's project control becomes the **unified picker**: a bar that
names the selected project and carries the two commands ruling 24 puts on top,
and a dropdown, opened only on demand, that lists every way in.

```
┌───────────────────────────────────────────────────────────┐
│ r1   [ New Claude session ]  [ New admin session ]  [ sessions ▾ ] │   ← the bar
├───────────────────────────────────────────────────────────┤
│ Sessions in r1                                        ✕   │   ← the dropdown
│   OpenCode                                              │   ← section labels
│   Review the failing tests                    3h ago    │
│   Claude · frontier                                     │
│   Ship the picker                             2m ago  Stop │
│   Admin · r1 running until 22:40        Stop  Open     │
│   New OpenCode session in r1 →                          │
└───────────────────────────────────────────────────────────┘
```

Three pieces, all front-end:

- **the bar** — the existing `#chat-project` control rebuilt: a label span with
  the project name, a **`New Claude session`** button, a **`New admin session`**
  button, and a caret control (`aria-haspopup="listbox"`, `aria-expanded`) that
  is the only thing that opens the dropdown. Ruling 24's top two buttons act on
  the *selected* project; the OpenCode command lives in the dropdown instead,
  which is why the caret is on the bar — the command it carries must be a tap
  away in one direction and findable in the list in the other.
- **the dropdown** — sections in a fixed order: OpenCode sessions, then Claude
  sessions (each group newest-touched first), a one-shot `New OpenCode session`
  row, and the running-admin-sessions section last. Data comes from the caches
  that already exist (`/api/sessions?project=`, `/api/hosts` per host,
  `running.js`'s `/api/launcher/status`) — the dropdown opens from cache
  instantly and refreshes in place. One new daemon call is *consumed*, none is
  added: the admin stop rides the existing `POST /api/launcher/stop` with
  `{"target": "admin", "project": P}` (ruling 24), the same channel as the
  Claude stop.
- **the admin hand-off** — `New admin session` is a link, not an RPC:
  `admin_origin + "/admin/sessions?project=" + encodeURIComponent(name)` opened
  top-level. Ruling 26's "no new channel" is about the daemon; a cross-origin
  redirect *is* the hand-off, and the iframe can only perform it as a top-level
  navigation (a2a §7: same-site paths framed, cross-origin never framed). The
  hub never fetches, POSTs to, or embeds an admin origin.

The picker keeps commit `6eed48f` verbatim: selecting a project closes the
dropdown and never opens it; the bar opens it on demand; Escape returns focus to
the bar control.

## 2. State, data and refresh timing

`hub/static/state.js` gains one key: `pickerOpen` (replacing `panelOpen`, which
nothing outside `sessions.js` reads today — verified by grep, a2a-9 §9 style).
The module-level view state stays inside `sessions.js`:

- `open` — whether the dropdown is shown. Project select sets it false (kept
  behaviour); only the caret control and Escape/click-away change it.
- `sig` — the last painted signature (project id, host list version, session
  list version, status version), so a background poll never re-lays-out rows a
  keystroke can land on (the existing `test_a_background_poll_never_steals_the_
  panel_or_the_focus` keeps holding).
- `pending` — the project id whose `New OpenCode session` row has been tapped
  and awaits the start response; while set, that row is inert and reads
  `Starting…`. One tap at a time: a second tap while pending does nothing.
- `creating` — the claude session id whose row is mid-start (claude.js keeps it,
  unchanged in behaviour, only in markup position).

Sources, all already fetched by existing pollers — the picker adds no timer:

| section | source | refresh |
|---|---|---|
| project list | the chat select's `projectList` store | when the store changes; select rebuilds the bar label |
| OpenCode + claude rows | `/api/sessions?project=P` per selected project — the same `fetchProjectSessions` path claude.js uses; the root key and the per-host relay paths are the ones `sessions.js` already implements | opening (from cache, then once), and when a poll's version moves while open |
| admin section + bar button state | `running.js`'s 10 s `/api/launcher/status` poll; the picker consumes `options.project_admin`, `options.admin_projects`, `options.admin_members` and the `target == "admin"` entries (`project`, `state`, `deadline`, `rc_name`, `link`, `member` — the shape a2a-3 fixes) | the poll repaints the dropdown in place when open |
| `admin_origin` per project host | `/api/hosts` rows (a2a-7: every row carries it, `""` when unset) | the existing hosts refresh that paints the rows |

**One-shot rows.** `New OpenCode session in <project>` is rendered only for a
project that has no OpenCode sessions (ruling 24: "the row disappears once a
session exists there"). OpenCode sessions have no stop (ruling 9 stands), and
this slice adds no per-project start button to existing rows — a project with
≥1 OpenCode session gets no `New OpenCode` row at all. This is the one place a
second OpenCode session cannot be started from the picker; named here so the
reviewer sees it was weighed, and listed under Out of scope.

## 3. Copy — verbatim, this is what the tests assert

All English, matching the existing UI's language. `{P}` is the project name
(rendered as text, never parsed), `{t}` a `HH:MM` local time from the deadline.

| where | text |
|---|---|
| bar label | the project name |
| bar caret button | `Sessions ▾` (the `▾` is the existing `BAR_CARET` glyph) |
| bar command 1 | `New Claude session` |
| bar command 2 | `New admin session` |
| dropdown heading | `Sessions in {P}` |
| close control | `Close` |
| section labels | `OpenCode`, `Claude · {name}` (existing host-row text, reused), `Admin · {P}` |
| empty project-list dropdown line | `No projects yet.` |
| no-sessions line | `No sessions here yet.` |
| one-shot row | `New OpenCode session in {P}` |
| one-shot row while pending | `Starting…` |
| create/list failure line | `Could not list these sessions.` + a `Retry` button |
| project not in broker.json | `Not in broker.json: no admin sessions for this project.` |
| `project_admin` off | `Admin sessions are off.` |
| no usable admin origin | `Needs the admin origin: A1 phase 2` |
| admin row, running | `running until {t}` |
| admin row, other states | the state string as reported (`starting`, `stopping`, `exited (rc 1)`, `gone`, `launch-failed`) |
| admin row buttons | `Stop`, `Open` |
| admin Stop confirm | `Stop the admin session for {P}? The browser tab it serves dies with it.` |
| admin stop failure | `Could not stop it: {detail}` + `Dismiss` |

A deadline renders as `new Date(deadline*1000)` → two-digit `HH:MM`; a deadline
that has passed renders `until overdue`. `aria-label`s repeat the visible words
plus the state (ruling 25); no hidden text carries information the visible UI
lacks.

## 4. Layout and theme

Reuses the existing visual language only — the `.chat-project` bar, the
`.claude-btn` command buttons, `.session-row` rows, `.session-section` labels,
`.session-empty` line, and the `--ink/--muted/--line/--card/--hover/--accent/
--bad` variables. No new colours, no new dependencies, no icon font.

The bar is the same 32 px grid row it is today (`#chat-project` keeps its box);
inside it the order is label, `New Claude session`, `New admin session`, caret.
At **390×800** the two commands shorten by CSS only: `.bar-btn .long { display:
none }` leaves **`Claude +`** and **`Admin +`** (both strings live in the DOM as
`<span class="long">Claude session</span><span class="short">+</span>` shapes so
assistive tech and the tests see full words); the label keeps `flex: 1` with
`text-overflow: ellipsis`, so the *label* clips and nothing else does; the bar
row never wraps and the page never scrolls horizontally (asserted, step 3). The
dropdown reuses the panel geometry: chat-pane wide under the bar, `max-height`
and scroll as today, rows keep the 44 px touch height, sections keep the 10.5px
labels. At 1440×900 the full copy shows. Light and dark both keep the panel on
the card tokens (the existing `test_a_dark_scheme_keeps_the_panel_on_the_card_
tokens` keeps holding).

## 5. Accessibility and keyboard

- Every action is a real `<button>` (rows that act are buttons styled as rows,
  as today), Tab-reachable, activated by Enter/Space. The caret control carries
  `aria-haspopup="listbox"` and `aria-expanded` true/false.
- Keys while open: ArrowDown/ArrowUp walk the focusable controls inside the
  dropdown, Home/End jump to first/last, Enter activates the focused control,
  Escape closes and returns focus to the caret control (the kept behaviour,
  retargeted from the old whole-bar button), Tab out of the last control closes.
  Keys while closed do nothing (no roving tabindex).
- Disabled states use `aria-disabled="true"` plus a real reason the UI shows —
  the button stays focusable and Tab order never breaks, and the reason is
  visible text, not only a tooltip: the command buttons get a sibling `.bar-note`
  (the existing `.claude-btn.disabled` treatment, visible under the bar on
  narrow screens), and the dropdown carries the matching line from §3. `title`
  is not used alone; a11y trees need not surface it for the state to be
  knowable. Tests assert `aria-disabled`, not `disabled`.
- The `Close` affordance: the caret button already carries the open/close
  toggle, so the dropdown's own close control is the **existing** panel close
  affordance if one remains after the rework, else nothing — no second `Close`
  button is invented, and the caret keeps its plain `Sessions ▾` text (the
  state rides `aria-expanded` alone; `aria-owns` links the list to the caret).

## 6. The admin hand-off, exactly

One function owns the URL, `hub/static/admin_link.js`:

```js
buildAdminHandoffUrl(origin) -> string | null
```

- Trim ASCII whitespace and `U+2000`–`U+200D`, `U+2028`, `U+2029`, `U+FEFF` from
  the ends (a pasted config value can carry them).
- If the result is empty, or contains any of space, tab, CR, LF, `,`, or a C0 or
  C1 control (`U+0000`–`U+001F`, `U+007F`–`U+009F`): return `null`. Never
  forward a possibly-multi-value line to `new URL()`.
- `new URL(raw)` must parse with `protocol === "https:"`, non-empty hostname, no
  credentials, empty `pathname` (`/` normalises to empty), and empty `search` and
  `hash`; otherwise `null`. (This is a2a §7's daemon-side validator restated in
  the front-end — both enforce it; neither trusts the other.)
- The usable hand-off URL is that authority plus `/admin/sessions?project=` plus
  `encodeURIComponent(projectName)`.

`New admin session` is rendered as `<a class="bar-btn" target="_top">` carrying
that href **plus `rel="noopener"`** (ruling 24's words) and a click handler that
sets `window.top.location.href` — anchor first because a real href is what makes
the state inspectable (focus, status line, `cmd`+click); the handler because a
cross-origin `target="_blank"` would leak the hub's `Referer` and pop a window
the UI can't see. Same for the `Open` button on an admin row: it navigates
top-level to the entry's `link`, which the daemon already validated; the front
never fetches it, never POSTs to it, never puts an admin origin in an iframe or
in `postMessage`. The daemon's `/api/launcher/start` is **not** used for admin
starts — ruling 24 routes them to the broker page.

Disabled mapping, in order: `options.project_admin` false → note `Admin
sessions are off.`; the project not in `options.admin_projects` → note `Not in
broker.json: no admin sessions for this project.`; the project's host row
`admin_origin` failing the guard (or `admin_members` not listing the user's
member — the hub hides its start button the same way today, so the picker
follows suit) → note `Needs the admin origin: A1 phase 2`. A null `options`
(status not fetched yet) renders the button enabled-looking but inert; the first
response repaints it. `aria-disabled="true"` always accompanies a note.

## 7. Trust boundary

Design §6 is the rule this UI exists to obey: **the hub's iframe list is the
only cross-origin content, and it is always same-site.** Everything the dropdown
touches goes through the hub origin — `/api/sessions`, `/api/hosts`,
`/api/sessions/relay/<hostId>/…`, the launcher-status fetch,
`POST /api/launcher/stop`, `POST /api/sessions`, `POST /api/launcher/oc/start`.
The one URL built from a daemon-supplied cross-origin value (`admin_origin`, a
`link`) is a top-level navigation target, never a `src`, never fetched, never
`postMessage`'d. An `admin_origin` the guard rejects renders the disabled note
and is never navigated to by any code path. Step 1's tests pin the guard's table
exhaustively.

Server-supplied strings (titles, host names, `rc_name`, states, details,
project names) reach the DOM **only** through `textContent`. Step 2's battery
feeds `<img src=x onerror=alert(1)>`, a right-to-left override (`U+202E`), and a
10 000-character title and asserts: rendered as text, clipped (`ellipsis`, no
wrap growth), no new DOM element, no script executed, and the row's click target
unchanged.

## 8. Steps and their boundaries

Three steps, each independently verifiable, every step's verify ending with the
full suite (`"hard": true` on all three):

1. **a2p-1-bar** — the bar: rebuild `#chat-project` (label span, two command
   buttons, caret control with `aria-haspopup`/`aria-expanded`); the
   `admin_link.js` guard + hand-off anchor + disabled mapping; the dropdown
   opens from the caret and closes on project switch, still rendering the
   *existing* body for now; `pickerOpen` in the store; kept behaviours re-pinned
   (no auto-open, Escape focus return, click-away, unpaired hub). Rewrites the
   pinned tests its spec names. Touches no daemon, no `hub/*.py`.
2. **a2p-2-dropdown** — the content: sections and rows in ruling 24's order,
   the one-shot OpenCode row with its `Starting…` pending state, the admin
   section (state, deadline, Stop via `launcher/stop`, `Open`, confirm, failure
   line), empty/loading/error+retry, the hostile-string battery, keyboard
   walking, repaint-sig stability, the not-in-broker/admin-off lines, and the
   real-daemon flow test that the stop POST body is exactly
   `{"target": "admin", "project": P}`.
3. **a2p-3-screenshots** — acceptance evidence: the browser test that saves the
   eight PNGs (§9), the phone-layout asserts, polish-only product edits.

## 9. Screenshot acceptance (the mechanism, because it bites)

`PageSession.screenshot` (`hub/tests/test_h2_browser.py:565`) returns the base64
PNG and writes to `$DELEGATE_EVIDENCE_DIR` **only when that variable is set**
(`:92`) — and the existing browser suites *skip* entirely without chromium
(`@unittest.skipIf(CHROME is None, SKIP_REASON)`, `test_h2_browser.py:89-90`).
The step-3 test therefore diverges on purpose: it builds its own output path —
`os.path.join(os.environ.get("DELEGATE_EVIDENCE_DIR") or "/tmp", "a2p-shots")` —
always writes the eight files itself from the returned base64, prints each path,
and a final check asserts the eight expected names exist and are non-empty; a
missing PNG fails the run. And **no `skipIf`**: `setUpClass` calls
`self.fail(SKIP_REASON)` when `h2b.CHROME` is `None`, so the suite reports FAIL,
not a skip, without a browser (task rule; deliberate divergence from the house
pattern, recorded in the step spec). Names:
`<w>x<h>-<light|dark>-<closed|open>.png` for 390×800 and 1440×900, the `open`
shots taken with the dropdown over the populated fixture list (two OpenCode
sessions, two claude sessions, one running admin), the `closed` shots showing
the bar with both commands. The fixture is built through the same fake-daemon +
hub harness as the other browser tests; its host is `hub.example.com`, its
project `code.example.com`.

## 10. Tests

- `hub/tests/test_a2p_bar.py` (step 1, new) — bar identity and order; caret-only opening (the ruling-24
  battery, DOM + browser); caret focus/ARIA/keyboard; hand-off guard table incl. the `</svg></a><img
  src=x onerror=alert(1)>` project; disabled-admin note; 390 px short labels. Step 1 also rewrites the
  pinned bar tests in `test_sessions_ui.py` (list in the step spec) and keeps the rest green.
- `hub/tests/test_a2p_dropdown.py` (step 2, new) — body order, one-shot row semantics, stop buttons per
  the trust table, the four trust strings rendered inert (`innerHTML` guard + a DOM assertion that no
  element with `tagName != 'LI'` appears inside `#chat-sessions-list`), refresh throttling, Escape/focus
  return, and the stop-row flow test against a real daemon (design §8; asserts the daemon's
  request.log). Step 2 rewrites the remaining body tests in `test_sessions_ui.py`.
- `hub/tests/test_a2p_browser.py` (step 3, new) — dark parity, caret state after close, disabled
  one-shot row, long-title render at 1440, plus the screenshot acceptance test (§9). It FAILS when no
  browser is present (unlike the repo's skip-without-chromium pattern): an environment that cannot
  prove step 3's acceptance cannot pass it.
- The trust battery (design §7) runs once per rendering surface — bar in step 1, dropdown in step 2 —
  and both assert `textContent` equality plus no-new-element and no-`innerHTML`-in-diff.
- Screenshot diffing across steps is manual (the lead reviews PNGs); the browser test asserts geometry,
  class, and file presence, not pixels.
- Full-suite cost is unchanged: one new module per step (three at cap-100). `tools/run_tests.py` caps at
  100 parallel modules (the browser ones are the slow tier, ~4 min); name them explicitly in verify
  commands for the fast path, exactly as the A2 step 6–8 chain does.

## Owner questions

- **Does `New admin session` open Claude directly, or offer a Claude/OpenCode
  split?** **Picked: it opens the broker page for the selected project, which
  is the Claude launcher** — no split menu. Ruling 24 gives the button one job
  (start a session in this project *and open the broker page that sees it*);
  only the Claude launcher can open that page. The OpenCode command needs no
  bar button because the dropdown carries it prominently as the one-shot row —
  a second OpenCode entry would imply the two commands are peers of the same
  kind, which they are not: one hands off, the other does not. A split would
  also put a chooser on the bar for a source the list has already chosen for
  you. If the owner wants a split anyway, the change is confined to step 1's
  second button.
- Section order: OpenCode first, Claude next, Admin last (a state to notice,
  not a command to reach). Pinned in step 2's spec; flip with a word from the
  owner.

## Out of scope

Per-frame origin badges (A2b, ruling 24), a project-agnostic launcher status
endpoint (A4), renaming "New session"→"New Claude session" outside the picker
bar (ruling 24 scopes the rename to the bar), a second OpenCode start on a
project that already has one (the one-shot row, §2), the A1 phase-2 broker
itself (this picker only links to it), and any change to the daemon, the relay,
or `hub/*.py`.

