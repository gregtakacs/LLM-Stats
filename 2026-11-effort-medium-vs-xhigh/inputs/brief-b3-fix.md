# i4-6: fix B3 at its cause (the flaky queue-parking test)

Owner, 2026-11-20: flaky project tests keep costing whole worker rounds. In this chain alone,
i4-2 rounds 1-2 and i4-4 round 2 failed only on B3 (docs/bugs.md): the root
`tools/{orb-tool}` package goes red at ~220 s on
`TestThePassParksForADemandAndResumesItsOwnQueue` (2 of 10 runs, documented 2026-11-10).

## Read first
- docs/bugs.md B3.
- The test and the code it drives in tools/{orb-tool} (find it with grep; read the queue
  parking/resume code it exercises).
- A worker's diagnosis from i4-2, read-only: {home}/.local/state/delegate/{orb-project}-integration-4-lead-i4-2-cards-take-glass/evidence (NOTES.md, gostress-a.log, gostress-b.log,
  b3-probe.log, gotest-probe.log).

## Do
1. Reproduce: `go test -count=200 -run '^TestThePassParksForADemandAndResumesItsOwnQueue$' .` from
   tools/{orb-tool}, under parallel load (e.g. `-cpu 1,4` and a second concurrent run); record the
   failure rate.
2. Find the cause. If it is the test's timing (a sleep, an unsynchronised read, a racy assertion),
   fix the test to wait on the real event. If the product code has a real race, fix the product
   code, and add a test that fails without the fix. Never skip, weaken, retry or loosen the test.
3. Prove it: the same command with -count=500, plus -race, 0 failures (show the commands and
   counts in EVIDENCE), and the whole tools/{orb-tool} suite green 3 times in a row.
4. docs/bugs.md: B3 status → fixed, one line on the cause and the commit.

## Scope
tools/{orb-tool}/**, docs/bugs.md. Nothing else. Do not run git merge/commit (the harness commits).
