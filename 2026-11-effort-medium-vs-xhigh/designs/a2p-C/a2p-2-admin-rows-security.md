# a2p-2 — Admin rows, the hand-off builder, the security suite

Part of [a2p-design.md](a2p-design.md) — read §5.4–5.5, §7, §3–§4 and §12 first; the row fields and
the a2a-3 host-row shape are already pinned in §5.1. Builds on a2p-1: the control, bar, shell and
reason line exist; `validateAdminOrigin`, `adminOriginFrom` and `handoffHref` are exported from
sessions.js. The step-6 contract exists in `docs/specs/a2a-design.md` (`project_admin`,
`admin_projects`, the launcher's `GET /projects/<name>`) but its code is not in this branch: every
step-6-field test scripts a `httputil.FakeLauncher` (pattern: `test_a2a_ui.py` l.551-630) and
asserts the UI's defensive behaviour.

## Acceptance criteria

1. One hand-off function: eligible activation calls `handoffHref(origin, project, "claude")` then
   `window.open(url, "_blank", "noopener")` — nothing else; the hub location never changes; no
   `fetch`, `XMLHttpRequest`, `<iframe>`, `<form>` or method argument anywhere on this path (proven
   by source guard + fake-server request count).
2. The admin row renders exactly one row per host row with a *valid* `admin_origin`; labels are
   `Display (host)` / `(unnamed host)` / `#<n>`; offline and pending hosts get the disabled form
   with verbatim reasons; a row never disappears.
3. The stop control follows the a2a §7 contract; the running-count chip counts only rows that are
   actually running; `fmtDeadline` and `STOP_CONFIRM_MS` are imported from running.js, not copied.
4. `test_a2p_rows_security.py` (13 tests, exact names below) green; full `python3 tools/run_tests.py`
   green including the untouched `test_own_origin_never_leaves_static_code`,
   `test_forbidden_tokens_never_appear_in_static_code`, and `test_ui.py`'s hosts-key-set pin (l.484:
   the payload keys stay exactly `{id, label, mode, reachable, error, admin_origin}`).

## Files owned

- `hub/static/views/sessions.js` — admin row render (anchor/button form per design §5.2), the
  hand-off activation (single handler entry; the anchor default covers click and Enter, plus a
  `keydown` guard for Space), the footer link (same builder, `agent=claude`), the reason channel
  with §3 precedence, `renderRunningChip`, the stop control, the stop-failure note.
- `hub/tests/test_a2p_rows_security.py` — new.
- `hub/tests/test_a2p_picker_source.py` — append `test_handoff_uses_only_construction_and_window_open`.
- Nothing else. If `test_ui.py`'s picker source guards trip (the setAttribute/textContent
  whitelists), fix it via a2p-1's §6 re-pin list — a2p-2's scope guard fails otherwise, and that is
  the design working: the anchor is a2p-1's.
- Read-only: running.js (`fmtDeadline`, `STOP_CONFIRM_MS`, `state.launcher`), index.html, app.css.

## Design → steps

**1. Admin row render.** For each host row (in `/api/hosts` order) with `adminOriginFrom`-valid
`admin_origin`: `.picker-row` containing `.session-row` (label via `textContent`; `title` only for
truncation) + the `#chat-admin` control. Label: `label.trim() ? `${label.trim()} (${host})` :
"(unnamed host)"`, `host` = `.hostname` of the parsed URL, empty → `#${i}` (0-based index + 1,
stable while row order is). Offline/pending → `aria-disabled="true"` +
`aria-describedby="chat-admin-reason"`; the row never disappears. The anchor's `href` is written with
`link.setAttribute("href", admin.href)` (never `link.href =` / `location.href =`; a2p-1 §6 re-pins
`test_ui.py`'s setAttribute whitelist to allow exactly this).

**2. Hand-off (the security spine).**
```js
export function openAdminUrl(project, origin) {
  const url = handoffHref(origin, project, "claude");   // design §5.4; throws on invalid origin
  window.open(url, "_blank", "noopener");
}
```
No other effect. The ineligible activation path (a2p-1's) reveals the §3 precedence reason in the
bar-level `#chat-admin-reason` line (design §2) and never touches the dropdown's open state. An
anchor with a non-https/validity-failing href renders as the ineligible form (defence in depth
against a store that skipped validation).

**3. Running chip + stop + 4 s deadline.** `renderRunningChip(rows)` → `Running N` (N = rows whose
session `status ∈ {starting, streaming, retrying}`) or `No running session` when zero — the chip
only ever counts rendered rows. Stop control per a2a §7:
`POST /api/hosts/<id>/launcher/sessions/<session_id>/stop` sending `{action:"command", cmd:"stop",
target:"admin", project:<the row's project>}` as JSON body, via the existing `daemon.stopSession`
wrapper; after a 2xx, show the deadline: `Stopping… <fmtDeadline(Date.now() + STOP_CONFIRM_MS)>`,
imported from running.js, which owns the exact 4000 ms constant (l.18) — do not restate it. A stop
failure shows a note with the response body's `detail` text (running.js l.188-210 is the idiom:
raw fetch, `body.detail`, text "That session did not take the stop.") — not a field called
`message`; copy or import `fmtDeadline`, never reach across module boundaries.

**4. Footer link.** Same builder with `agent=claude`; text `"Admin page →"` (textContent); renders
`rel="noopener noreferrer"` regardless of any earlier `rel` value (append to `relList`, no exact
string equality in tests).

**5. No inline handler attributes anywhere;** the test below asserts the absence.

## Tests in `test_a2p_rows_security.py` (real browser; names exactly)

`test_handoff_never_uses_fetch_form_or_iframe` (source guard + fake-server request count: zero
requests fired after activation; asserts `window.location` unchanged) ·
`test_anchor_rel_is_token_set_in_any_order_and_target_blank` ·
`test_handoff_href_exact_encoding` (project with a space, `alpha beta`: URLSearchParams encodes it
as `alpha+beta`; the test pins the builder's return string exactly and asserts decoding round-trips
to the original bytes — `%20` vs `+` is pinned as behaviour, not aesthetics) ·
`test_handoff_href_has_no_path_prefix_and_no_second_encoding` (`agent=two words` → exactly one
`+`/`%20`, never `%25`) · `test_origin_from_hosts_row_not_setting` (override
`window.hubConfig.admin_origin` to a decoy; hand-off still uses the host row's URL) ·
`test_invalid_origin_never_launches_row_survives` (`javascript:alert(1)`, `http://admin.example.net`,
`https://u:p@admin.example.net/`, `https://admin.example.net/y` as scripted host rows) ·
`test_stop_request_body_exact_and_project_scoped` (FakeLauncher records the stop body:
`{action:"command", cmd:"stop", target:"admin", project:"alpha"}` plus the token field; no header-
derived fields, no session URL in the body) · `test_running_chip_zero_vs_rows` (1 `starting` + 1
`stopped` → `Running 1`) · `test_deadline_is_4s_via_imported_constant` ·
`test_unnamed_label_empty_and_whitespace_forms` (`""` and `"   "` → `(unnamed host)`) ·
`test_row_index_survives_reordered_list` · `test_no_inline_handler_attributes` ·
`test_offline_and_pending_rows_disabled_with_reason`

## Verify

```
python3 tools/run_tests.py hub.tests.test_a2p_rows_security hub.tests.test_a2p_picker_source \
  hub.tests.test_ui hub.tests.test_c1a1_browser hub.tests.test_a2e_ui hub.tests.test_a2a_ui
test -z "$(git diff --name-only HEAD | grep -vE \
  '^(docs/specs/a2p|hub/static/views/sessions\.js|hub/tests/test_a2p_rows_security\.py|hub/tests/test_a2p_picker_source\.py)$')" \
  && echo SCOPE-OK
```