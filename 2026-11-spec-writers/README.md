# Three agents write the same implementation spec

**Result.** A fresh frontier agent with no prior context wrote the best spec. A self-hosted
local model, run through a delegation harness, came a close second: as accurate and the most
thorough, but it missed two of the owner's rulings that live only in the orchestrating agent's
saved notes. The orchestrating agent's own spec, written with the files already in its context,
was correct but the thinnest. The local model's gap was knowledge, not reasoning: given the
rulings, it should write specs about as well.

## The project

Firmware and a companion desktop app for a round smart display: an ESP32-S3 board with a
466x466 round AMOLED panel, a rotary knob, an SD card and Wi-Fi. The firmware runs third-party
apps as WebAssembly modules, draws themed faces from flash and serves an HTTP API. A desktop
"hub" finds the displays on the network, flashes firmware, installs apps and themes, and hosts
the theme editors in a web page.

| Part | Language | Size |
|---|---|---|
| Firmware (ESP-IDF, LVGL, wasm3) | C | 77,600 lines in 153 files |
| Hub | Go | 73,500 lines, of which 36,500 are tests |
| Hub web page | JavaScript | 23,000 lines |
| Theme editors and shared runtime | JavaScript | 36,900 lines |
| Apps (compiled to wasm) | C | 6,300 lines |
| Build, bake and host-test tools | Python | 49,600 lines |
| Design and planning docs | Markdown | 33,000 lines (the main plan alone is 7,900) |
| History | | 1,253 commits in about a month |

## The task

One step of a feature that makes app installs land live, with no reboot of the device: the
hub's half. On firmware that reports `live_install`, the hub must stop waiting for restarts that
no longer happen, wait for the new app's ledger row to say `built:true`, still restart once when
a batch owes it (an update), and the page must read right. Specifying it needs the firmware
contract it consumes, a 1,887-line install flow, about 8,000 lines of page code, and the tests
that pin today's behaviour.

All three writers got the same brief: the owner's rulings for the feature, the firmware step's
spec, the same one-paragraph goal, and the same spec-writing rules (real names only, a verbatim
contract, checks that cannot pass silently, an explicit out-of-scope list).

The writers:

- **A. Fresh agent:** a frontier coding agent in a new session, no prior context.
- **B. Local model:** a self-hosted model, run by a delegation harness in an isolated worktree
  with the live checkout mounted read-only.
- **C. Orchestrator:** the frontier agent that had been running the project all day, with the
  relevant files already read.

## Time and tokens

| | A. Fresh agent | B. Local model | C. Orchestrator |
|---|---|---|---|
| Wall-clock | 9 min 40 s (about 5 min of it a baseline test run) | 10 min 51 s | 31 s measured; warm context. Cold, estimated 6-10 min |
| Work | 32 tool calls, almost all sequential | 150 tool calls, 134 steps | about 7 KB read, 5 KB written |
| Tokens out | ~11,000 (its own estimate; no counter) | 59,106 (measured; self-hosted, no API cost) | ~4,000 new |
| Tokens in | ~40,000-50,000 (150-200k characters, estimated) | not measured | plus the session's context, mostly cached |
| Spec size | 21.9 KB | 24.1 KB | 5.1 KB |
| Cost for the orchestrator to review it | ~8,000 tokens | ~8,000 tokens | none |

## Quality

Facts were spot-checked against the code by the orchestrator: every function, test, make target
and line number a spec named.

| Criterion | A. Fresh agent | B. Local model | C. Orchestrator |
|---|---|---|---|
| Names and line numbers accurate | 10 of 11 (the miss is a test file it says to create) | 9 of 10 exact, 1 off by 5 lines | yes, fewer named |
| Restart row on live firmware | dropped (matches the owner's "no 'not needed' rows") | kept and marked skipped (against that ruling) | dropped |
| When a restart is due | precise, including an update whose card copy must be re-sent | covered | partial |
| New app vs update decided before the install, with the reason | yes | yes | weaker |
| A distinct step word for a live landing | yes | yes | no (reused one the flow counts as "a reboot is coming") |
| Test-double changes the tests need | partial | most thorough | missing |
| Page text | done line and uninstall prompt | step wording only | none |
| Checks that cannot pass silently | yes; counts the PASS lines | mostly | yes |
| Bench safety on the real device | separate hub on its own port, filtered to the one device, scratch library copies, killed afterwards, no firmware push | starts a hub on the owner's own port | no bench |
| **Rank** | **1st** | **2nd (close)** | **3rd** |

Both A and B caught a subtle hang in the existing install flow (a new app installed in a batch
would sit in a deferred wait until the timeout). C missed it.

## Could the local model work unsupervised?

- **Writing specs: nearly.** Its reading of the code matched the fresh agent's. Both of its misses
  were project rulings recorded only in the orchestrator's saved notes, which the fresh agent (a
  session on the same machine) most likely saw and the local model could not. Mounting those
  notes, or moving the rulings into a file in the repo, should close most of the gap.
- **Implementing: not yet for firmware.** In an earlier step of the same feature the local model
  shipped a crash-level object-lifetime bug (UI objects left attached to a deleted page), caught
  only in review. Work with good tests, and firmware it benches on the real device itself, is
  close. A short review aimed at the owner's rulings, concurrency and object lifetimes is still
  worth its few thousand tokens.

## Files

- [specs/A-fresh-agent.md](specs/A-fresh-agent.md)
- [specs/B-local-model-delegate.md](specs/B-local-model-delegate.md)
- [specs/C-orchestrator-warm.md](specs/C-orchestrator-warm.md)
- [results.csv](results.csv)

The specs are unedited apart from the placeholders.
