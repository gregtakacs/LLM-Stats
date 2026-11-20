## a2p — scores (0–2)

| # | Criterion | A | B | C | D |
|---|---|---|---|---|---|
| 1 | Rulings fidelity | 1 | 1 | 0 | 0 |
| 2 | Boundary coverage | 2 | 2 | 1 | 1 |
| 3 | Hard flags and verifies | 2 | 1 | 0 | 1 |
| 4 | Step sizing and order | 2 | 2 | 1 | 1 |
| 5 | Executability | 1 | 1 | 0 | 1 |
| 6 | Owner questions | 1 | 2 | 0 | 1 |
| 7 | Errors | 0 | 1 | 0 | 0 |
| | **Total** | **9** | **10** | **2** | **5** |

Verdicts: A: accept after small fixes (wrong hand-off URL path, one-shot OpenCode row, invented store/CSS names) / B: accept after small fixes (drop the FAIL→ok log rewrite, fix the dark-mode mechanism, add `&agent=`) / C: needs a rewrite (admin button not on the bar, wrong stop endpoint, fabricated base facts, verifies that cannot pass) / D: needs a rewrite (the two bar buttons' roles inverted, project-free stop body)   Rank: B > A > D > C

## a2p — evidence

Checked against the base `4c60732` (a2a-design §7 is the contract: link `<admin_origin>/?project=<P>&agent=claude|opencode`, stop `POST /api/launcher/stop {"target":"admin","project":P}`). All four chain JSONs parse and have `name/repo/base/gate/retries` and `steps[].name/spec/verify/hard/scope`. Every spec path resolves. C's top level also carries an extra `spec` key (a2p/C/a2p-chain.json:7).

**1. Rulings fidelity**
- A (1): the bar is right: two commands plus a separate caret, no auto-open (a2p/A/a2p-design.md:41-47, 64-66). But the hand-off URL is `admin_origin + "/admin/sessions?project="` with no `agent` (design.md:57-58, 197-198; a2p-1-bar.md:108-109), which contradicts a2a §7. "New OpenCode session" shows only when the project has zero OpenCode sessions (design.md:95-101; a2p-2-dropdown.md:54-62). That contradicts ruling 9's clarification ("be able to start one from it") and ruling 24, and the reason given is a wording ruling 24 does not contain. Rulings are also mis-cited: "Ruling 26's 'no new channel'" (design.md:59) and "(ruling 25)" for aria-labels (design.md:133).
- B (1): bar and dropdown are correct (a2p/B/a2p-design.md:36-43). But the link deliberately drops `agent` (design.md:89-92, a2p-2-admin-handoff.md:100), against the contract. Ruling 24 is "quoted" in words it does not have (design.md:13-17). The disabled copy `Project admin is off: enable project_admin in admin.json` (design.md:122) replaces the contract's "not configured". Rulings 25/26 are mis-cited for disabled states (design.md:73-74, 99).
- C (0): the bar has "exactly two controls" `#chat-project` and `#chat-claude-new`, and New admin session is a row inside the dropdown (a2p/C/a2p-design.md:44-46, 120-134; a2p-1-bar-controls.md:10-12). That contradicts ruling 24. The visible copy stays `New session in <project>` against ruling 24's "New OpenCode session" (design.md:138-140). Stop goes to `POST /api/hosts/<id>/launcher/sessions/<sid>/stop` (design.md:182-184), not `/api/launcher/stop`.
- D (0): "New admin session" is the dropdown toggle and "New Claude session" is the admin hand-off (a2p/D/a2p-design.md:24-38, 51-54; a2p-2-dropdown-handoff.md:136-138). That inverts ruling 24, where New Claude = Claude·frontier in the project container and New admin = the hand-off. The stop body is `{"target":"admin"}` with no project (design.md:77-79; step 2:147-149), against a2a §7.

**2. Boundary coverage**
- A (2): an exhaustive origin-guard table, with neighbours beyond the brief: port, `//host`, `javascript:`, `data:`, `file:`, comma, `\n`, `\t`, U+2028, U+0001, zero-width, trimming (a2p-1-bar.md:95-109). Click asserts no `fetch` (:116-118). Hostile battery with `window.__xss` and `children.length` (a2p-2-dropdown.md:85-92). Exact stop body from the daemon log (:35-40). Project isolation of the session list is not stated.
- B (2): URL table plus encoding cases (a2p-2-admin-handoff.md:96-107). A navigation-only test: one GET Document, zero POSTs toward the admin origin (:130). The href is re-validated each paint when the origin changes mid-session (design.md:103-106). Also covered: stop 409, status unavailable, closed on switch, hostile `rc_name`/member/project names (:126-141).
- C (1): no-fetch proof, rel token set and a decoy origin (a2p-2-admin-rows-security.md:82-99). But the stop-body test pins the wrong body (`{action:"command",cmd:"stop",…}`, :93-95). No session-list isolation.
- D (1): concrete origin-rejection and encoding cases (step 2:154-155, 166-170), and a project-switch stale-data case (:179-180). But the disabled states sit on the wrong button (design.md:49-56), and the stop assertion pins the project-free body (:162-164).

**3. Hard flags and verifies**
- A (2): all three steps are hard. Each verify runs the full gate, greps its own and neighbouring modules, and guards scope against the previous step's branch including untracked files (a2p/A/a2p-chain.json:27, 42, 55). Step 3 checks all 8 PNGs. The browser test fails rather than skips (a2p-3-screenshots.md:198-199).
- B (1): the verifies rerun failing modules and rewrite `FAIL` lines to `ok` in the evidence log (`sed -i -E "s/^FAIL( +$m )/ok\1/"`, a2p/B/a2p-chain.json:25, 39, 53), so a flaky real failure is laundered. Step 1 is `hard:false` and does not run the gate (:11, 25) even though it re-renders the session list. The step-2 browser module uses `skipIf` (a2p-2-admin-handoff.md:123-124). The PNG count in step 3 does catch a missing browser (:53).
- C (0): steps 1–2 never run the full gate (a2p/C/a2p-chain.json:24, 35). The `| tee` is used without `set -o pipefail`, so the runner's exit code is lost. The verifies name modules that do not exist at base (`test_a2d_ui`, `test_a2f_ui`, `test_a2e_ui`, `test_a2a_ui`). The scope guard is `git diff HEAD`, so committed rounds escape. The last step is `hard:false` (:40).
- D (1): steps 2–3 run the full gate with module greps, and step 3 checks the 8 PNGs (a2p/D/a2p-chain.json:34, 49). No verify has a scope guard. Step 1 is `hard:false` and not gated (:11, 21).

**4. Step sizing and order**
- A (2): three steps of plausible size in the right order. Minor: the caret id differs between steps (`#chat-project-caret` at a2p-1-bar.md:61 vs `#ap-toggle` at a2p-3-screenshots.md:192). Step 1 oddly owns all spec files (a2p-chain.json:14-18).
- B (2): steps are sized and ordered right (design.md:230-239). Step 1 is wide but coherent.
- C (1): step 1 owns markup, sessions/claude/running.js, app.js and the test_ui re-pins. Step 2's scope is only `sessions.js` plus tests, yet it needs CSS and test_ui changes (a2p-chain.json:30-34; a2p-2-admin-rows-security.md:35-37).
- D (1): step 1 turns `#chat-project` into a `div` (design.md:25-30). That breaks `test_sessions_ui`'s pins, but that file is neither in step 1's scope nor in its verify (a2p-chain.json:12-21). The chain sits red until step 2.

**5. Executability**
- A (1): names not at base: `fetchProjectSessions`, `_startCreate`, `BAR_CARET`, `Project.apiFetch`, stores `projectList/chatProject/claudeHosts`, `set_store` (a2p-2-dropdown.md:30; a2p-1-bar.md:85-87, 117; a2p-3-screenshots.md:162). "`pickerOpen` replacing `panelOpen`" is wrong because `pickerOpen` already exists (design.md:70). CSS variables `--muted/--card/--hover/--bad` are not in app.css (design.md:140). The test-line references are accurate (a2p-1-bar.md:121-133).
- B (1): the core names are real (`renderAdminLink`, `_world_answer`, `claudeAvailable`, `fmtDeadline`, `askStop`, `tickClocks`, `TestSessionPickerInSource`, `lastSignature`). Step 3 invents `_set_theme`, "chromedriver" and `a2a-design §7.6` (a2p-3-a11y-screenshots.md:197-199, 238). `#a2h-admin-link` is invented too (design.md:84).
- C (0): base facts are fabricated. `#chat-project-clear`, `aria-haspopup="listbox"` and `role="listbox"` are not in index.html. The `CLICK_AWAY_EXEMPT` literal is wrong (design.md:12-25). Also invented: `test_click_away_exempt_selector_pinned`, `launcherStale`, `window.hubConfig`, `Claude Code not enabled on this launcher`, and an "a2a-4 i18n test" (design.md:83, 140, 230). `PageSession(cdp).screenshot(str(path))` misuses the helper (a2p-3-browser-shots.md:163). It also relies on `node --check` (a2p-chain.json:24).
- D (1): mostly real (`stopBody`, `_validate_stop`, `BAR_HIDDEN`, `/api/oc-projects`, `launcher_unavailable`, `STATE_WORDS`). `setPickerOpen` is invented (a2p-1-picker-bar.md:26). Step 1's scope is too narrow (it omits test_sessions_ui).

**6. Owner questions**
- A (1): answers the required question, but the reasoning is muddled ("only the Claude launcher can open that page", design.md:308-318). The one-shot-row restriction is assumed instead of asked.
- B (2): the required question gets a picked answer and a cost (design.md:195-201). Two further real gaps: a bar state dot and shortening the empty copy (:202-210).
- C (0): Q2 re-decides ruling 24's copy (design.md:320-322). The required question is folded into Q1.
- D (1): Q1 is framed on the misread button (design.md:178-181). Q3 (same-tab vs `<a>`) and Q4 are real.

**7. Errors**
- A (0): the hand-off goes to `/admin/sessions?project=` (a2p-1-bar.md:108-109), a page the admin origin does not serve (its page is `hub/static/admin/index.html` at `/`), so the main action breaks. `admin_members` not listing a member disables admin (design.md:213-216), but per a2a §7 it only controls the member picker. Users cannot start a second OpenCode session from the picker.
- B (1): the FAIL→ok rewrite in every verify (a2p-chain.json:25). Dark mode is done by toggling `html.dark` (a2p-3-a11y-screenshots.md:272-273), but the app themes only through `prefers-color-scheme` (app.css:29), so the "dark" shots would be light.
- C (0): the wrong stop endpoint and body (design.md:182-184). The admin entry is missing from the bar. The verify pipe masks failures (a2p-chain.json:24).
- D (0): the `{"target":"admin"}` stop with no project (step 2:147-149) targets the host `cc-admin` unit, not the project's session. The New Claude button navigates away instead of starting a container session (step 2:136-138). It adds a second 10 s status poller beside running.js (design.md:119-122).

## a2x — scores (0–2)

| # | Criterion | A | B | C | D |
|---|---|---|---|---|---|
| 1 | Rulings fidelity | 1 | 1 | 1 | 0 |
| 2 | Boundary coverage | 1 | 2 | 2 | 1 |
| 3 | Hard flags and verifies | 1 | 0 | 2 | 0 |
| 4 | Step sizing and order | 2 | 1 | 1 | 2 |
| 5 | Executability | 1 | 0 | 1 | 1 |
| 6 | Owner questions | 2 | 2 | 2 | 1 |
| 7 | Errors | 1 | 0 | 1 | 0 |
| | **Total** | **9** | **6** | **10** | **5** |

Verdicts: A: accept after small fixes (scope guard against the previous step, drop "workers commit", add the header-claim and helper-socket cases, use a registry check) / B: needs a rewrite (invented error codes and test modules, verifies that cannot pass, live probes that contradict the design) / C: accept after small fixes (step 1 too large, a few invented codes and test files, the AX-S3 home write) / D: needs a rewrite (misattributed rulings, a live script that runs inside the container, a verify that cannot pass)   Rank: C > A > B > D

## a2x — evidence

All four chain JSONs parse and have the required keys. Every step is `hard:true`, so the brief's acceptance check passes. D's top level also carries `timeout` (a2x/D/a2x-chain.json:6).

**1. Rulings fidelity**
- A (1): the two layers, the read-only live script and the fake-docker unit tests are correct (a2x/A/a2x-design.md:7-16, 194-198). But "Workers commit" (design.md:42; a2x-1-broker-write-hostile.md:103) contradicts the brief's never-commit rule. Ruling 26 is given words it does not contain (design.md:190-191). The preflight uses `docker ps` labels instead of the registry (a2x-4-live-container-probes.md:147-149).
- B (1): the layers, `docker exec --user 1000:1000`, the registry refusal and docker-missing exit 2 are correct (a2x/B/a2x-design.md:247-251, 277-279). But L7 `touch /etc/passwd /usr/local/bin/x /run/x` attempts writes outside /tmp (design.md:261). Step 5 widens into `review/a2x-hostile.py` and `docs/handoff.md` (design.md:322-329). It cites a nonexistent "ruling 24c" (:126).
- C (1): faithful on layers, the registry guard via `oc.projects.load_registry`, the container user, and the docker-missing exit (a2x/C/a2x-design.md:275-298; a2x-4-live-acceptance-script.md:26-39). But AX-S3 writes a sentinel to `~` inside the container, a persistent bind (design.md:311). That breaks no-write-outside-/tmp, and the design's own skip rule contradicts it (:287-290).
- D (0): the rulings are mislabelled with fabricated quotes: "Ruling 24: a suite, not a page…" and "Ruling 25: the container layer…" (a2x/D/a2x-design.md:10-17). Rulings 24/25 are the picker rulings. The live script runs inside A's container via stdin with `sudo docker exec` (design.md:209-215). The brief asks for a host script that does `docker exec` itself.

**2. Boundary coverage**
- A (1): strong neighbours: hard-link `st_nlink` gap, `GIT_CONFIG_GLOBAL` leak, `.git` swap, double-planted links, registry TOCTOU, metadata IP (design.md:71-97, 131-134, 182-183, 215). But the relay list has no `X-Forwarded-*`/`Host` claim case (design.md:156-168). There is no helper-socket probe (:203-228), and FIFO/device and non-finite numbers are left to existing suites.
- B (2): broad, concrete rows B1–B31, R1–R9 (forged identity headers, Host/421, smuggling, response-header drops) and M1–M6, each with a side-effect oracle (design.md:150-183, 222-232, 296-303).
- C (2): enumerates the whole brief list (design.md:14-24), then gives concrete ids: B1–B15, F1–F10 (TOCTOU, hard link, FIFO, device), G1–G6 with a marker file, R1–R13 including `X-Forwarded-*` and cross-project WS, and M1–M7. Neighbours include Origin, cookie floods and caps (design.md:140-264, 302-313).
- D (1): the list is covered, but many cases are merged into single rows with alternative outcomes, e.g. XB9 "`bad_request` / `too_large`" for nine poisons and XB7 for five path attacks (a2x/D/a2x-design.md:143-145). XR4 lists reserved names `broker`, `hub` that are not in `RESERVED_PROJECT_NAMES` (:163; broker/config.py:55-56).

**3. Hard flags and verifies**
- A (1): every step runs the full gate, its module grep and the FAIL grep. But the scope guard diffs against `merge-base HEAD a2-steps-6-8`, not the previous step (a2x/A/a2x-chain.json:24, 40, 55, 65). In steps 2–4 the earlier steps' files fall outside the allowed regex, so those verifies fail on a correct chain.
- B (0): the verifies grep modules that do not exist at base (`hub.tests.test_relay`, `hub.tests.test_projects`, `hub.tests.test_proxy_hardening`, a2x/B/a2x-chain.json:54, 81), so steps 3 and 5 cannot pass. No step has a scope guard, although the design promises one (design.md:339-341).
- C (2): full gate plus own-module greps, and a scope guard against the previous step's branch (base for step 1) (a2x/C/a2x-chain.json:17, 29, 40, 50). Step 4 asserts that dry-run with no registry exits 2.
- D (0): step 1 requires `broker.tests.test_anonymity`, which does not exist (a2x/D/a2x-chain.json:17), so it always fails. Every verify also has the FAIL→ok `sed` rerun (:17, 28, 39, 50).

**4. Step sizing and order**
- A (2): four steps split by component, each ~100 lines of spec and plausible in 90 minutes, in the right order.
- B (1): step 3 combines K1–K10 and R1–R9 across two components with fixes (design.md:315-317). Step 5 is a closeout that edits handoff and adds a second script (:322-329). The id K9 is used twice (:206-207).
- C (1): step 1 carries B1–B15, F1–F10, G1–G6, C1–C6, a new `fakebin.py` and a `_strings` fix (design.md:335), roughly 37 cases, unlikely in 90 minutes.
- D (2): four steps of reasonable size in the right order (design.md:263-268).

**5. Executability**
- A (1): names are mostly verified real (`read_inside`, `GIT_ENV`, `FORCED_CONFIG`, `arg_echo`, `MAX_CONNECTIONS`, `REASONS`, `MAX_SOURCE_BYTES`, `_image_or_refuse`, and the cited test names). Invented: `broker/bin/request`, which is load-bearing for case 1 and probe 4 (design.md:65, 211), and `HARD_CONFIG_KEYS` (:89). `oc/tests/util.py` and `launcher/tests/util.py` do not exist but are scoped as "helpers may be added" (a2x-chain.json scope; a2x-2-install-plan-hostile.md:30).
- B (0): invents error codes against the explicit rule: `invalid_request`, `toolarge_value`, "no such op", `unsafe_git_arg`, `bad_service_name`/`SERVICE_PRE_SPAWN_CODES`, `copy_too_large` (design.md:155-157, 161, 164, 175). It also invents test files `test_peer.py`, `test_repocheck.py`, `hub/tests/test_relay.py`, `test_proxy_hardening.py` and `oc/image/Containerfile` (:73, 95-100, 152).
- C (1): mostly real (`_strings`, `MAX_LINE`, `admit`, `_run_safely`, `body_project_offline`, `_check_mount_value`, `load_registry`). Invented: the `not_member` code, `NotAGitRepo`, `MAX_ARG_LEN` and `FAKE_BIN_LOG`, and the test files `test_gate_a2a.py`, `test_a2h_auth.py`, `test_repocheck.py`, `test_groups.py` (design.md:63-66, 149, 170, 111).
- D (1): mostly real (`require_task`, `child_cwd`, `check_argv`, `FORBIDDEN_FLAGS`, `request_headers_for`, `_forward_target`, `ERROR_STATUS`, `SEGMENT_RE`). Invented: `refused_argv`, `ProjectError`, `accept_is_refused`, the `from_fd` seam and the `/run/{project}/sock/<B>/` paths (design.md:152, 182, 196, 235). Scopes are globs `broker/*.py`, `hub/*.py`, `oc/*.py` (a2x-chain.json:14, 25, 35), far too wide.

**6. Owner questions**
- A (2): nlink rule, metadata IP, hub-down SKIP and soak placement are all real gaps with picks (design.md:279-286).
- B (2): the DANGEROUS_KEY extension, one or two scripts, and the same-uid boundary (design.md:345-359).
- C (2): the BiDi/control refusal fix, newline inertness, one request per connection, SKIP policy, fakebin and cutover order (design.md:349-368).
- D (1): Q1 asks about a delivery choice the design itself invented, and Q5 (step count) is trivial (design.md:284-297).

**7. Errors**
- A (1): the scope guard blocks the chain at step 2 (a2x-chain.json:40). The commit instruction (a2x-1-broker-write-hostile.md:103) conflicts with the brief's never-commit rule. Neither ships a hole.
- B (0): the invented codes plus §3's "a failing case is a component bug, fix the component" (design.md:114-118) would push workers to change the broker's wire codes. L3 expects the container's own socket to be not writable, and L8 expects the container's own connect to be refused (design.md:257, 262). A correct deployment then FAILs, or the probes pressure the owner to break the broker.
- C (1): AX-S3's home write (design.md:311). Pinning the invented `not_member` (:65, 170) would drive a code change. AX-B7 broadens protocol refusals on a promise that `a2-2a` does not state at base.
- D (0): the in-container registry at `/run/{project}/projects.json` (design.md:226-228, 287-289) would need a registry of every project mounted into each container, which leaks other projects. The verify log laundering is the same as above. P9 has the operator plant a sentinel in the project env file (a2x-4-live-hostile.md:57-60).
