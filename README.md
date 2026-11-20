# LLM-Stats

Small, honest measurements of LLM coding agents doing real work on a real project, not
benchmarks. Each experiment keeps its inputs, outputs, numbers and the assessment together, so
the results can be checked rather than taken on trust.

| Date | Experiment | One-line result |
|---|---|---|
| 2026-11 | [Three agents write the same implementation spec](2026-11-spec-writers/) | Claude Code (Opus 5.5) wrote the best spec; a self-hosted Qwen 3.8 Flash Next (pennyroyal build) on an RTX 6000 PRO was a close second, and its gap was project knowledge, not reasoning. |
| 2026-11 | [Medium vs xhigh reasoning effort on hard work, same local model](2026-11-effort-medium-vs-xhigh/) | On a real concurrency fix and two security/UI slice designs, Qwen 3.8 Flash Next (pennyroyal) at medium effort matched xhigh: every fix survived 1,000 race-checked runs either way, and blind design scores totalled 29 vs 27. xhigh took 25–70% longer. Two runs at the same effort differed far more (10 vs 5, 9 vs 2) than the two efforts did. |
| 2026-11 | [A frontier model and a local model plan the same security-heavy slice](2026-11-security-slice-planning/) | On a security-boundary slice, Qwen 3.8 Flash Next (pennyroyal, xhigh) wrote a plan that failed its own first gate and missed neighbour cases; Claude Opus 5.5 (Medium) as lead wrote one that ran as written. Blind scorers from both models agreed; the Qwen scorer missed the worst defect. |

Names, addresses and local paths are replaced with placeholders such as `{owner}`, `{orb-ip}`
and `{home}`.

## Tools

- [`tools/sanitize.py`](tools/sanitize.py) copies an experiment's raw artifacts to a publishable
  folder, applying an ordered list of regex replacements, then fails if any deny pattern still
  matches:

  ```bash
  python3 tools/sanitize.py ~/.config/llm-stats/sanitize-rules.json raw/ 2026-11-my-test/
  ```

  - The rules file holds the very names it removes, so it lives **outside every repo**. Start
    from [`tools/sanitize-rules.example.json`](tools/sanitize-rules.example.json).
  - A deny-list only finds what you thought to list. After a clean run, also sweep the output
    for IP addresses, e-mail addresses and hostnames you didn't expect.
