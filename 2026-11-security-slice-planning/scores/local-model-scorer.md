# H3 blind plan score: X vs Y

Both plans read in full; every named file/function spot-checked against `1f19283`; both chain JSONs valid in delegate's format; both verify greps checked against `tools/run_tests.py`'s real output (`OK$` patterns do catch `OK (skipped=N)` for modules they grep).

**X = 5/14, Y = 11/14. Y wins; X's chain cannot pass its own step-1 verify as written.**

| # | Criterion | X | Y |
|---|---|--:|--:|
| 1 | Rulings fidelity | 1 | 2 |
| 2 | Boundary coverage | 1 | 2 |
| 3 | Hard flags and verifies | 1 | 1 |
| 4 | Step sizing and order | 1 | 2 |
| 5 | Executability | 1 | 2 |
| 6 | Owner questions | 0 | 1 |
| 7 | Errors | 0 | 1 |

**1 — Rulings.** Y reflects §3/§5/§10 cleanly: the renewal frame is served on the OpenCode host but framed by the hub page and settled by `postMessage("{project}-renewed")` checked in both `event.origin` and `event.source` (Y/plan-4:32,50); the sign-in link goes top-level to the OpenCode origin. X misses two rulings: it tests `GET /api/me` with an opencode Host → 421 (X/plan-1:113) while R-H3-2 makes the opencode role relay everything but `/h/` specials, and step 3 has OpenCode's own page frame the renewal with the sign-in link pointing at the hub's `/api/login` (X/plan-3:8,68) — the §5 model inverted.

**2 — Coverage.** Both carry the brief's neighbours (Host case/port, a host in both roles, `null` Origin, sibling Origin, `/hubx`, `/%68ub/`). Y goes past it: `/hub//evil.example` must 404 never redirect (Y/plan-2:83), gate-before-308 ordering, caps+1 and zero-verifier bodies, `/h/_hub/renew.html;x` and `%72enew.html`, doubled slashes, per-host vs domain cookies, forged `postMessage`, `/pty/x` WS on the opencode role. X adds `%2e%2e`, an appended-CSP probe, `http://` Origin — but its 308 `Location` is `"/"+raw rest` verbatim (X/plan-2:69): exactly the open redirect Y blocks.

**3 — Hard flags and verifies.** Y's hard flags match design §8 exactly, and step 1 OK-greps all three browser modules so skips fail it. Its flaw: the hard step-2 verify deliberately excludes those modules (Y/plan-2:6-7) — documented, but against AGENTS.md's "hard = both suites in full". X flags step 2 light while it carries the 308, which §8 puts in hard step 1, and its step-2 verify greps only `test_routing`, so a skipped `test_h2_browser` passes silently.

**4 — Sizing.** X's step 1 is design step-1 plus config+gate+proxy+api plus 19 test modules, framing, sw.js and both layouts: well over ~1500 lines for one session. Y splits the same design step into two hard steps of plausible size; its light step-3 (UI move) is heavy but carries a real spike.

**5 — Executability.** Both cite only real symbols (`route_for`, `_step_origin`, `_public_host_ok`, `hosts_payload`, `OriginDevTools` all present). Y's scope guards are per-file regexes with negative guards (`git diff --quiet … -- hub/static …`); X's are `^(hub/|docs/specs/plan-)` everywhere — wide enough to hide drift into `hub/static` and `hub/doctor.py` on steps that forbid them. Y ships `plan-3-front-spike.py` proving the https-front the browser tests need; X has no TLS story and keeps non-443 ports in the Origin compare (X/plan-1:77-80), forcing the portless-https fixtures at hub/tests/httputil.py:579 and test_sessions_ui.py:71 to be rewritten under it.

**6 — Owner questions.** Neither plan asks the owner anything (grepped); both left the test-https and installer-ordering gaps to themselves. Y closes them with documented deviations (H4 narrowing, the browser-red step 2) — better than silence but no flag that sign-off was owed; X hedges a settled §5 ruling, which the rubric discounts.

**7 — Errors.** X's fatal: step 1 refuses any hub.json containing `public_hosts` (X/plan-1:68) while forbidding a touch to `install.sh` (X/plan-1:56), and the installer keeps writing that key (hub/install.sh:852) with hub/tests/test_install.py:350,848 installing then calling `load_hub_config`. `test_install` goes red at step 1 and step 1's hard full-suite verify can never pass; steps 2–3 stay red. The rubric's "would its chain have passed?" answers itself: no, at the first gate. Second bug: the 308 open redirect. Y's literal follow-ons: a hard step shipped with three modules knowingly red, and Origin byte-equal to `https://`+port-stripped Host (Y/plan-1 §3) 403s a genuine `https://host:port` on any non-443 deployment — fine for this deployment, a portability trap.

**Borrow.** X→Y: its two-hostname `BrowserStack` section with an owned fake OpenCode upstream (X/plan-2:76-83) is clearer than Y's; step 4 names `daemon/tests/test_install_docs.py` in scope. Y→X: per-file scope guards with negatives, the spike script, the never-redirect 308 policy, the `postMessage` renewal handshake, and OK-grepping browser modules in every hard step.

**Verdict.** Run Y. It matches the binding rulings, beats the brief's neighbour list, keeps the suite green at every step bar one it documents, and its worst sin is priced in the open. X has better UI-move prose and honest flags but fails the disqualifying test twice — its own verifies cannot pass as written, and followed literally it ships a chain-breaking bug plus an open redirect. Land Y's shape, import X's BrowserStack section, and fix Y's step-2 verify to run both full suites with sign-off before any exclusion.
