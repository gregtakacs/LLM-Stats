# LLM-Stats

Small, honest measurements of LLM coding agents doing real work on a real project, not
benchmarks. Each experiment keeps its inputs, outputs, numbers and the assessment together, so
the results can be checked rather than taken on trust.

| Date | Experiment | One-line result |
|---|---|---|
| 2026-11 | [Three agents write the same implementation spec](2026-11-spec-writers/) | Claude Code (Opus 5.5) wrote the best spec; a self-hosted Qwen 3.8 Flash Next (pennyroyal build) on an RTX 6000 PRO was a close second, and its gap was project knowledge, not reasoning. |
| 2026-11 | [A frontier model and a local model plan the same security-heavy slice](2026-11-security-slice-planning/) | On a security-boundary slice, Qwen 3.8 Flash Next (pennyroyal, xhigh) wrote a plan that failed its own first gate and missed neighbour cases; Claude Opus 5.5 (Medium) as lead wrote one that ran as written. Blind scorers from both models agreed; the Qwen scorer missed the worst defect. |

Names, addresses and local paths are replaced with placeholders such as `{owner}`, `{orb-ip}`
and `{home}`.
