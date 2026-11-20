# a2p-1 — the picker bar: two commands, the guarded admin hand-off, dropdown skeleton

Authority for this step: `docs/specs/a2p-design.md` §1, §3 (bar copy), §4, §5,
§6. Binding upstream: `docs/specs/a2-design.md` ruling 24 (verbatim button
names, dropdown behaviour) and commit `6eed48f` (kept behaviour, §6 of the
design).

## Goal

Rebuild the chat header's project control into the unified picker's bar: label,
**`New Claude session`**, **`New admin session`**, caret control; add the
admin-hand-off URL guard `hub/static/admin_link.js` and wire the hand-off anchor;
make the dropdown open only from the caret and close on project switch, its body
still the *current* rows rendered under the new open/close model (step 2 reworks
them into the unified list). After this step the picker looks and keys like the
final thing; it just lists the old rows.

## Read first

`docs/specs/a2p-design.md`; rulings 24–26 in `docs/specs/a2-design.md`;
`docs/specs/a2a-7-hub.md` (the `hosts_payload` row carrying `admin_origin`) and
`docs/specs/a2a-3-units.md` (the status entry fields this step consumes);
`docs/specs/a2a-9-admin-page.md` (the page the hand-off opens); the current
`hub/static/views/sessions.js`, `hub/tests/test_sessions_ui.py`,
`hub/static/views/claude.js` (`paintSection`'s disabled handling),
`hub/static/views/running.js` (status cache, `poll`), `hub/static/index.html`,
`hub/static/app.css` (the `.chat-project`, `.session-picker`, `.claude-btn`
rules).

## Files owned

- `docs/specs/a2p-design.md`, `docs/specs/a2p-1-bar.md` — this step re-ships
  them with the two adjustments below (the spec step owns the spec files: it is
  the only step whose diff may touch `docs/specs/`, and it makes exactly the
  adjustments the REVIEW records, nothing else).
- `hub/static/admin_link.js` — new: the guard, exported as
  `Project.buildAdminHandoffUrl`; nothing else.
- `hub/static/index.html` — the bar markup and the dropdown shell; content-hash
  bump (no test asserts the hash value; grep confirmed).
- `hub/static/views/sessions.js` — bar rendering, open/close state, disabled
  mapping, hand-off wiring. The existing panel body (claude section, OpenCode
  rows, list states) keeps rendering inside the dropdown **unchanged** in this
  step — its rework to the unified layout is step 2's job; keep it working.
- `hub/static/app.css` — bar layout, `.bar-btn`/`.bar-caret`/`.bar-note`, the
  390 px short-label rule (§4), `aria-disabled` styling mirroring
  `.claude-btn.disabled`.
- `hub/static/state.js` — `pickerOpen` replaces `panelOpen` (check callers;
  `app.js` tab-dot and `_selectProject` touch points move here).
- `hub/tests/test_a2p_bar.py` — new: the DOM battery below.
- `hub/tests/test_sessions_ui.py` — rewrite the pinned tests listed below; do
  not touch any other test file.
- `docs/specs/a2p-1-bar.md` (this file).

## Contract

1. **Bar** — `#chat-project` stays a labelled container (`role="group"`,
   `aria-label="Project picker"`); inside, in order: `#chat-project-label`
   (span, the project name via `textContent`, ellipsis), `#bar-btn-claude`
   (`<button>`, text `New Claude session`), `#bar-btn-admin` (**`<a>`**, text
   `New admin session`, `target="_top"`, `rel="noopener"`, href per §3 below),
   and `#chat-project-caret` (`<button>`, text `Sessions ▾`,
   `aria-haspopup="listbox"`, `aria-expanded`). All tabbable in DOM order. At
   ≤520 px the two command buttons show `Claude +` and `Admin +` (full words
   live in spans, §4 of the design); every other rule about the old whole-bar
   button (32 px grid row, ellipsis on the label only) holds.
2. **Open/close** — the dropdown (`#ap-dropdown`, a `div[role=listbox]` built
   inside `#session-picker`) is shown iff `pickerOpen`; only the caret (and its
   keys) opens it; selecting a project closes it (kept behaviour); click-away
   closes it (the exempt list in `CLICK_AWAY_EXEMPT` covers the new controls);
   Escape closes it and focuses `#chat-project-caret`; Tab off the last control
   closes it. Opening shows the heading `Sessions in {P}` above the retained
   body, and `No sessions here yet.` when there are no sessions — the row rework
   is step 2's.
3. **The guard + hand-off** — exactly the design §6 rules. The anchor's href is
   the guarded URL with `encodeURIComponent(project)`; a rejected origin means
   no href attribute at all (`removeAttribute("href")`), `aria-disabled="true"`,
   `tabindex="-1"` dropped from tab order is *not* used — the anchor stays
   focusable — and a `.bar-note` sibling reading `Needs the admin origin: A1
   phase 2`. `options.project_admin === false` → same disabled shape, note
   `Admin sessions are off.`; project absent from `options.admin_projects` →
   note `Not in broker.json: no admin sessions for this project.`; `options`
   null → enabled-looking, inert until the first status lands (design §6).
4. **New Claude session** — same action the picker's claude section has today
   (create on the selected project's host with its key, the `_startCreate`
   path), just relocated to the bar; one tap, one POST, in-flight disables.
5. **Stores touched**: `projectList` (name), `chatProject` (selection),
   `claudeHosts` (host row → `admin_origin`), and the launcher status the page
   already fetches — `running.js` keeps owning the 10 s
   `POST {action:"status"}` poll; the bar reads the same response object's
   `options` / `sessions` fields the a2a steps added. No new poll, no new
   store key beyond `pickerOpen`, nothing in `hub/*.py` touched.

## Tests to write (`hub/tests/test_a2p_bar.py`, plus the rewrites)

Guard table (every row, exact return value): `https://admin.example.com` ok;
`https://ADMIN.example.com` ok (scheme case-insensitive, host case preserved);
`https://admin.example.com:8443` **ok — a port is legal, pin it**;
`https://admin.example.com/` ok (the hand-off URL has exactly one slash);
`http://x`, `ftp://x`, `ws://x`, `https://x/p`, `https://admin.example.com/p`,
`https://x?q`, `https://x#f`, `https://u:x@h`, `https://:8443`, `https://` alone,
`javascript:alert(1)`, `data:text/html,x`, `file:///etc/passwd`, `/admin`,
`//admin.example.com`, ``, `   `, `https://a b`, `https://a,b`,
`https://a\nhttps://b`, `https://a\t`, `https://a\u2028`,
`https://a\u0001`, `https://a\u200b` (zero-width space is **not** in the trim
set — reject, pin it), padded ` https://admin.example.com/ ` ok,
` https://admin.example.com ` ok — every rejection is `null`, every acceptance
is the parsed `https://<authority>` string with no trailing slash. Hand-off URL:
origin `https://admin.example.com` + project `r 1/é` →
`https://admin.example.com/admin/sessions?project=r%201%2F%C3%A9`.
DOM battery (`test_a2p_bar.py`): bar has the four controls in order with the
exact texts; `aria-expanded` flips; **selecting a project never opens the
dropdown** (the kept behaviour, re-pinned here too); Escape returns focus to the
caret; the four disabled-state mappings render `aria-disabled="true"`, the exact
note text, and an anchor with no `href`; a host row whose `admin_origin` is
`http://x` renders the A1-phase-2 note (the guard's rejection is the UI's
rejection); the hand-off anchor as rendered carries `rel="noopener"`,
`target="_top"`, and a click does not call `fetch` (assert via a patched
`Project.apiFetch`).
Rewrite the pinned tests in `hub/tests/test_sessions_ui.py`. This step owns
exactly these (bar- and panel-open-behaviour ones); the rest of the module keeps
passing against the retained body and belongs to step 2's rewrite: line 145
`BAR_TEXT` → assert `#chat-project-label` holds the bare name (`"r1"`, no caret
— the caret text moved into its own control); 767 (phone: the picker moves to
the chat tab and the dot rule keeps holding — retarget selectors, change
nothing else); 806 (choosing a project leaves the dropdown closed, the caret
opens it); 823 (keyboard: Enter/Space on the caret opens, Escape closes and
returns focus to `#chat-project-caret`, arrows walk *the bar's* controls); 851
(click-away closes without touching the chat); 864 (the bar names the project
and the dropdown reopens after a choice); 884 (a background poll never steals
the open dropdown or the focus — same assertion, new ids); 941 (unpaired hub:
the notice shows and no picker control is live). The session-list, relay,
auth-path, touch-size and dark-scheme tests (433, 448, 471, 485, 524, 554, 575,
589, 601, 667, 699, 715, 728, 757) stay untouched and must stay green — they
pin the body this step keeps rendering.

## Acceptance criteria

- `python3 tools/run_tests.py hub.tests.test_a2p_bar hub.tests.test_sessions_ui
  hub.tests.test_ui` exits 0 with each module's summary line `ok`.
- The step's verify (chain JSON) additionally runs the **full suite** and greps
  the evidence log for the gate line and the new module.
- `git diff` shows no change outside Files owned; `claude.js`/`running.js`
  untouched; no daemon/hub-python file touched.
- Every copy string renders via `textContent`; a grep over the diff shows no
  `innerHTML` added to `sessions.js`/`admin_link.js`.

## Out of scope

Dropdown contents beyond the empty-state line (step 2), screenshots (step 3),
row-level CSS step 2 needs, any daemon change, any `title=` tooltip carrying
state.

## Worker rules for this host (lead, 2026-11-19)

- Tests run through `python3 tools/run_tests.py`; while iterating run only this
  step's modules; run the full suites once, at the end — this step's verify
  runs them too.
- **Never run git history or branch commands** — no `merge`, `commit`, `rebase`
  or `stash`; delegate saves the round, and a worker-made commit has produced
  objects the host repo could not see. The scope guard in this step's verify
  reads your `git diff`. Read-only git (`status`, `diff`, `log`, `show`) is fine.
- The gate also runs on the owner's host: **umask 002**, **`XDG_CONFIG_HOME`
  exported**. Do not code around either. Every test that creates a file the
  code checks for its mode sets that mode explicitly; every test that replaces
  `HOME` also sets (or removes) `XDG_CONFIG_HOME`, `XDG_DATA_HOME`,
  `XDG_STATE_HOME` under its temp dir. Never read or write the real home.
- **Anonymity is part of the contract**: `hub/tests/test_anonymity.py` (in
  the gate) rejects real hostnames in fixtures and test output — use
  `hub.example.com`, `code.example.com`, `admin.example.com`.
- New browser tests use free ports (`httputil.free_port()`), never fixed ones —
  the runner executes modules side by side, and two tests on one port collide.
- If chromium cannot launch, a screenshot test must **fail**, not skip.

