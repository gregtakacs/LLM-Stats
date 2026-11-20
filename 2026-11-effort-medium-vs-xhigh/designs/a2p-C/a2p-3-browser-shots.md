# a2p-3 — Browser proofs: widths, themes, the eight screenshots

Part of [a2p-design.md](a2p-design.md) — read §9–§12 first; owner ruling 25 (the screenshot matrix)
is the contract. Builds on a2p-1 + a2p-2; final step of the chain, so it runs the full gate.

## Acceptance criteria

1. `hub/tests/test_a2p_shots.py` green: the layout tests at 390×800 and 1440×900 (dropdown closed
   and open, light and dark) plus the a11y/keyboard/a11y-tree tests, all on the real CDP stack.
2. Exactly eight PNGs exist on disk under `${DELEGATE_EVIDENCE_DIR:-/tmp}/a2p-shots/`, named
   `390x800-light-closed.png` `390x800-light-open.png` `390x800-dark-closed.png`
   `390x800-dark-open.png` `1440x900-light-closed.png` `1440x900-light-open.png`
   `1440x900-dark-closed.png` `1440x900-dark-open.png`; a missing file fails the suite, it does not
   skip (no `test_maybe_`-style guard in this module). The verify command below additionally checks
   all eight exist at the exact names after the run.
3. Read every PNG (the delegate report lists observations per image).
4. Full `python3 tools/run_tests.py` green, including `test_anonymity.py` over these docs.

## Files owned

- `hub/tests/test_a2p_shots.py` — new.
- `docs/specs/a2p-design.md` — §10 contract table checked off (only if a2p-1 left a discrepancy to
  record; otherwise untouched).
- Nothing else. Any product-code bug this step exposes is reported, not patched here.

## Tests in `test_a2p_shots.py` (names exactly)

`test_no_control_overflows_at_390` (both controls fully inside the viewport rect, closed state) ·
`test_bar_wraps_at_390_and_dropdown_clears_it` (dropdown top ≥ bar bottom; panel within the
viewport) · `test_layout_stable_across_schemes` (control rects identical, ±1 px, light vs dark) ·
`test_dropdown_opens_without_view_change` (session-list view content unchanged) ·
`test_screenshots_written_eight` · `test_aria_and_focus_contract_live` (control's
`aria-haspopup`/`aria-expanded` live; focus moves into the panel on open and back on Escape; an
ineligible admin row's activation shows the bar-level `#chat-admin-reason` line, leaves the
dropdown closed, and keeps focus on the row; the line is announced — it carries `role="status"`;
`getAccessibilityTree` shows the control as a button) · `test_textcontent_only_degeneration_safe`
(script a session titled `<img src=x onerror=alert(1)>` plus an RTL override and a bidi control
character in the project label; assert `textContent` round-trips and no element matching `img`
appears inside the panel) · `test_long_values_clipped_not_overflowing` (10000-char project title;
row rects inside the panel rect) · `test_hover_focus_visible` (`:focus-visible` outline computed
non-none on the control and the admin row) · `test_prefers_reduced_motion_collapses_transitions`
(`prefers-reduced-motion: reduce`: computed transition durations ≤ 10 ms)

## Screenshots — exact mechanics

Reuse `test_c1a1_browser.py`'s CDP stack by import (it already renders at 390 and 1440 and drives
the picker: its `open_picker` helper clicks `#chat-project`, which is exactly what ruling 24 makes
permanent — zero edits there). Scheme flip: `Emulation.setEmulatedMedia` with
`features: [{name: "prefers-color-scheme", value: "dark"}]` — that file already uses the call
(~l.322); extend its small wrapper helper once, locally in this module. Shot helper here:

```python
def shot(cdp, width, height, scheme, state):
    path = SHOTS / f"{width}x{height}-{scheme}-{state}.png"
    PageSession(cdp).screenshot(str(path))   # absolute path; the repo helper writes bare
                                             # filenames into DELEGATE_EVIDENCE_DIR
    assert path.exists(), path
```

`test_screenshots_written_eight` loops widths × schemes × states with the dropdown opened via
`#chat-project`; the other layout tests assert geometry but take no PNG (one test owns the matrix;
no duplicate captures). The scripted state for all eight: one host with
`admin_origin: "https://admin.example.com"`, `project_admin: true`,
`admin_projects: ["alpha"]`, sessions `["alpha", "streaming"]` and `["beta", "stopped"]`.

## Verify

```
python3 tools/run_tests.py hub.tests.test_a2p_shots
test "$(ls "${DELEGATE_EVIDENCE_DIR:-/tmp}/a2p-shots" | wc -l)" = 8 && ls "${DELEGATE_EVIDENCE_DIR:-/tmp}/a2p-shots"
python3 tools/run_tests.py   # full gate — last step of the chain
test -z "$(git diff --name-only HEAD | grep -vE '^(docs/specs/a2p|hub/tests/test_a2p_shots\.py)$')" \
  && echo SCOPE-OK
```
