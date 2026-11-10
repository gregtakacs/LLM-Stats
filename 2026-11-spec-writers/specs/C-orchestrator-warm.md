# Hub: installs that land live

## Goal

docs/app-platform-plan.md §63, the hub's half of step C (`.delegate-specC.md`): on an orb whose
apps listing says `"live_install":true`, a NEW app loads and lands on the glass with no restart,
and only an update of an app already running restarts (it is owed, `restart_owed`). The hub's
install run must stop planning and waiting for restarts that will not happen, wait for the new
app's ledger row to say `"built":true`, and still restart once when the run owes it. On firmware
without `live_install`, nothing changes.

## Read first

- `docs/app-platform-plan.md` §63; `.delegate-specC.md` items 2, 5, 6 (the orb's facts).
- `tools/orb-manager/internal/orbnet/apps.go`: `AppList` (`RestartOwed`, `Defers`, `Owes`), `AppInstalledRow`.
- `tools/orb-manager/installflow.go`: `installRun` (the app loop: `landed`, `rebooted`, `cycled`,
  `batch`, `owed`, `restartOwed`; the tail's `waited`/`waitOrbCycle`), `installOneApp` (its poll
  after the install: the `deferred` branch with `Owes`, the non-deferred branch that sends
  `installed` / `restarted`), `installPlan` (the `restart` row), `runPhases.phaseOf`.
- `tools/orb-manager/installflow_test.go`: `TestABatchRestartsTheOrbOnce` (the fake orb to
  imitate), `TestASeedGoesBeforeTheRestart`, `TestTheRunSaysItsPlanFirst`.

## Contract

1. `AppList` gains `LiveInstall bool \`json:"live_install"\``; `AppInstalledRow` gains
   `Built *bool \`json:"built"\`` (nil from older firmware). New method
   `func (l *AppList) Lands() bool` → `l != nil && l.LiveInstall`.
2. `installOneApp`: after posting a non-deferred or deferred install on an orb that `Lands()`,
   a NEW app (no `installed` row for the slug in the listing read before the install) is done
   when its installed row has `Built != nil && *Built`: send
   `installStep{Step: slug, Action: "installed", Note: "on the dial now, no restart"}` and
   return. It does not wait for a reboot and does not look at `Owes`. An app that was already
   installed (an update) keeps today's behaviour exactly (deferred: wait for `Owes`;
   otherwise: the reboot). A `TryStem == slug && TryWhy != ""` still refuses as today. The
   poll gives up after `installHard` with today's message.
3. `installRun`: an install of a new app on a `Lands()` orb does not count as `landed` for the
   restart (it is not owed, it does not set `rebooted`, it does not add to `owed`). Updates
   count as today. Add a local `live := listing.Lands()` and track per slug whether it was
   already installed, from the listing read before the loop.
4. `installPlan(lib, slugs, card, chooses, seeded)` gains `lands bool` and `installed map[string]bool`
   (the slugs already installed): when `lands` is true and no slug in the run is already
   installed, the plan has NO `restart` row. Otherwise as today. Update its callers
   (`installRun` passes `listing.Lands()` and the installed set; read the listing before the
   plan is sent, as the run already reads it, or move the plan send after that read — keep
   the plan the run's FIRST streamed line).
5. The run's tail: with nothing rebooted and nothing owed, no `restarting` step and no
   `waitOrbCycle` (today's `waited := !rebooted || cycled` already gives this when `rebooted`
   stays false — verify it).

## Behaviour and edge cases

- Mixed run on a `Lands()` orb (one new app, one update): the new one lands live during the
  loop; the update is owed; one restart at the end; the plan has the `restart` row.
- Older firmware (`live_install` absent): byte-for-byte today's requests, plan and waits.
- The theme seed (before the apps on choosing firmware) is untouched.

## Acceptance criteria

1. `bash -c 'set -o pipefail; cd tools/orb-manager && test -z "$(gofmt -l *.go internal/orbnet/*.go)" && go vet ./...'` → exit 0.
2. New test `TestANewAppLandsLive` (installflow_test.go), a fake orb in the style of
   `TestABatchRestartsTheOrbOnce`, three cases, each asserting the requests the fake saw and
   the plan's ids:
   a. `live_install:true`, weather not installed: one install, no `/api/v1/reboot`, the
      installed row turns `built:true` after the install; the plan has no `restart`; the run
      ends without a restart wait (give `installRebootWait` a large value and assert the run
      returns quickly).
   b. `live_install:true`, weather installed (an update) + flights new, batch: one reboot at
      the end; plan has `restart`.
   c. no `live_install` key: exactly today's behaviour (the same assertions
      `TestABatchRestartsTheOrbOnce` makes).
3. `bash -c 'set -o pipefail; cd tools/orb-manager && go test -count=1 .'` → ok.

## Out of scope

- Firmware (`main/`), apps, `web/` (the page draws the hub's plan rows as they come, so a run
  without a `restart` row shows none; no page change is needed — say so if you find otherwise).
- The Themes face's missing-app offer and the setup journey: they run `installRun` and inherit this.

## Notes

- Do not commit; the orchestrator reviews and commits.
- No orb: these are fake-orb tests. The live bench runs after step C's firmware is on Gold.
