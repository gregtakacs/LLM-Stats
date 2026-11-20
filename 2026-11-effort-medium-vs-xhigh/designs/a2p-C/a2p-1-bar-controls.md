# a2p-1 — Bar controls: the picker control, New Claude, the admin row

Part of [a2p-design.md](a2p-design.md) — read its §1–§3, §5.1–5.3/5.6–5.7/5.9, §6, §9–§12 first;
this file is the work order. The base is `a2-steps-6-8` @ `4c60732`, which includes `6eed48f`
(the toggle-restore commit): `#chat-project` is the bar control AND the picker toggle; there is no
`<select>` in the chat view and no separate toggle.

## Acceptance criteria

1. Two controls in the chat-view bar: the project picker control `#chat-project`
   (`aria-haspopup="listbox"`, `aria-expanded` true only while the dropdown is open) and
   `#chat-claude-new` (states per design §4). The picker dropdown contains `#chat-admin`:
   eligible = an anchor with `href` + `target="_blank"` + `rel="noopener noreferrer"`; ineligible =
   `aria-disabled="true"` + `aria-describedby="chat-admin-reason"`. Every §3 state renders with its
   verbatim copy.
2. The dropdown opens only from the control (6eed48f preserved: selecting a project never opens it
   and closes an open one), closes on outside click, Escape, and project switch; it does not change
   the current view. `node --check` clean on every touched file.
3. Ineligible/rejected activation of `#chat-admin` shows the reason in the bar-level
   `#chat-admin-reason` line and does NOT open, close, or otherwise touch the dropdown (ruling 24).
4. New `hub/tests/test_a2p_picker_source.py` green, every test named exactly as in §Tests below.
5. Full `python3 tools/run_tests.py` green, including `test_ui.TestSessionPickerInSource` in its
   re-pinned form (§6 re-pins below) and the untouched `test_own_origin_never_leaves_static_code`.

## Files owned (this step alone)

- **Owned**: `hub/static/index.html` (chat bar + panel skeleton; the panel div keeps id/`role`/
  `hidden`/`aria-labelledby`); `hub/static/views/sessions.js` (control label, dropdown shell,
  `.picker-row` building, admin row + bar reason line, close/focus handling); `hub/static/app.js`
  (`renderAdminLink` via `validateAdminOrigin`); `hub/static/app.css` (selector extension only —
  design §10); `hub/static/views/claude.js` (start button → `#chat-claude-new` states, dispatch
  selector widened, `paintSection` reads `state.launcher` snapshot); `hub/static/views/running.js`
  (poll sets `state.launcherStale`; nothing else); `hub/tests/test_ui.py` (re-pins in §6 below —
  this step rewrites the markup that suite pins, so it must ride in the same commit);
  `hub/tests/test_a2p_picker_source.py`; `docs/specs/a2p-design.md` (§10 contract table filled).
- **Read-only for this step** (don't edit): anything in `running.js` beyond the `launcherStale`
  line; the launcher pill block in `index.html` and `#launcher-refresh-note`.

## Design → steps

**1. `validateAdminOrigin(value) -> URL | null` (sessions.js, exported; pure).**
`u = new URL(value)`; on throw → null; require `u.protocol === "https:"`, empty `username`/
`password`, empty `search`/`hash`, `pathname` in {`""`, `"/"`}; port allowed.
`adminOriginFrom(state)` = first host row (in `/api/hosts` order) whose `admin_origin` validates,
else null. `adminEligible(state)` = `project_admin === true && selected project ∈ admin_projects`.
`adminReason(state)` returns design §3's precedence text (the stale-error note only when
`state.launcherStale`). `handoffHref(origin, project, agent)` = `new URL(origin)` with
`searchParams.set("project", project); searchParams.set("agent", agent)`; return `u.toString()` —
one encoding, no path prefix.

**2. Bar markup.** `#chat-project` becomes `type="button"` and carries
`aria-haspopup="listbox" aria-expanded` (+ the existing `aria-controls="session-picker"`); its
label is the selected project's display name or "All projects" (same label source as the
`#chat-project-filter` sync line in app.js). A `.chat-bar` row holds the control and
`#chat-claude-new`: claude.js `paintSection`'s `devButton("claude-start", …)` now renders into the
bar; keep the exact `claudeSignature` memoization honest by folding the two launcher booleans into
it. Directly after the bar row: `<p id="chat-admin-reason" class="picker-note" role="status"
hidden></p>`.

**3. Dropdown = control-activated only.** The control toggles (click, Enter, Space); every other
activation path leaves the dropdown's open state untouched (ruling 24). The document click handler
(sessions.js l.45-55) exempts the control, the bar row, the reason line and the panel — as the
exact literal `CLICK_AWAY_EXEMPT = "#chat-project, #chat-claude-new, #chat-admin-reason, #session-picker"`
(the handler's body is `e.target.closest(sel)` with the selector appearing ONLY as that one
argument). Opening builds the panel rows; closing removes them; project switch closes and rebuilds;
Escape closes and focuses the control.

**4. Admin row = state-dependent.** Eligible: `<a id="chat-admin" class="chat-admin"
target="_blank" rel="noopener noreferrer">` with the href set via `setAttribute("href", admin.href)`
— never a `location.href =` / `window.location =` assignment: the own-origin guard
(`test_ui.py` l.123-132) scans every static file and fails on either. Ineligible:
`<button id="chat-admin" class="chat-admin" type="button" aria-disabled="true">` — a real button
(a `disabled` one swallows focus and the click that must reveal the reason). Ineligible activation:
show `adminReason(state)` in `#chat-admin-reason` and stop — no navigation, no `window.open`, no
dropdown state change. Eligible activation (click or Enter/Space) does exactly one thing: hands off
once to the anchor default, no custom action — the handler that guarantees this is a2p-2's.
`state.launcher === null` renders the pending state; it never removes the row.

**5. Focus model (design §9).** Control ↔ panel only: open → first enabled row or the New OpenCode
row; Escape → control; Tab cycles the panel; focus on a removed node → control; no focus movement on
close otherwise.

## §6 — test_ui.py re-pins (same commit; re-pin, never delete)

`TestSessionPickerInSource` (l.1241-1344) pins this panel's source; this step rewrites that source.
Each re-pin keeps the guard's intent:
- shell identity (l.1296-1305): `aria-controls` stays; the "no raw `<button>` inside the panel"
  count re-pins to 0 for the unwrapped region (the picker's buttons live inside `.picker-row`
  wrappers); option markup assertions re-pin to `.picker-row > .session-row` with the same
  textContent rules.
- setAttribute whitelist (l.1267-1281): extends to allow exactly the fixed new values
  `aria-controls→session-picker`, `aria-haspopup→listbox`, `aria-expanded→true|false`,
  `aria-disabled→true`, `aria-describedby→chat-admin-reason`, `href→admin.href`, `target→_blank`,
  `rel→noopener noreferrer`, `hidden→""`; the data-* rule is untouched (only `dataset.session`
  writes, ≤3 total; `link.relList.add("noreferrer")` is fine).
- `.textContent =` RHS whitelist (l.1287-1292): grows by exactly `row.title`, the five §3 reason
  strings and `"Admin page →"`; the `item.title` count pin moves 4 → 6 (control label, option
  titles, two bar-button titles, admin row title).
- `.chat-project` rule (l.1327-1333), `.session-picker` geometry (l.1318-1326) and the
  `.session-picker::-webkit-scrollbar` rule (app.css l.342): keep every pinned token.

## Tests in `test_a2p_picker_source.py` (names exactly)

`test_bar_has_picker_control_and_claude_button_no_select` ·
`test_project_control_carries_listbox_aria` ·
`test_control_toggles_dropdown_panel_below` ·
`test_selecting_project_never_opens_dropdown` ·
`test_selecting_project_closes_open_dropdown` ·
`test_control_is_the_only_opener` ·
`test_ineligible_admin_shows_bar_reason_without_touching_dropdown` ·
`test_reason_line_hidden_before_first_activation` ·
`test_new_claude_disabled_states_per_precedence` ·
`test_row_survives_null_launcher_state` ·
`test_no_event_propagation_to_view_change` ·
`test_click_away_exempt_selector_pinned` ·
`test_footer_admin_link_rel_and_href_shape` ·
`test_render_never_touches_location_or_form`

The source-text tests import and reuse `test_c1a1_ui.py`'s file-read + assert helpers; don't
re-implement them.

## Verify

```
python3 tools/run_tests.py hub.tests.test_a2p_picker_source hub.tests.test_ui \
  hub.tests.test_c1a1_ui hub.tests.test_c1a1_browser hub.tests.test_a2d_ui \
  hub.tests.test_a2f_ui
node --check hub/static/views/sessions.js && node --check hub/static/views/claude.js \
  && node --check hub/static/app.js && node --check hub/static/views/running.js
test -z "$(git diff --name-only HEAD | grep -vE \
  '^(docs/specs/a2p|hub/static/(index\.html|app\.css|app\.js|views/(sessions|claude|running)\.js)|hub/tests/(test_ui|test_a2p_picker_source)\.py)$')" \
  && echo SCOPE-OK
```
The scope clause fails the step when the diff leaves the list. A source guard tripped in another
suite is fixed by re-pinning the pin, never by relaxing behaviour.
