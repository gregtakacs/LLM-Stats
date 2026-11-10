# Hub: installs that land live

## Goal

docs/app-platform-plan.md §63, the hub's half of the app rows ("added: it is installed, loaded
and lands on the glass at once"; "deleted, on the glass: the dial moves to the next app").
Firmware step C (`.delegate-specC.md`) makes a NEW app land live with no reboot and reports it
in `GET /api/v1/apps` as a top-level `"live_install":true` plus `"built":true|false` on each
`installed` row; an update of an app already built this boot still restarts (it is owed, in
`restart_owed`). This step makes the hub's install run, on an orb that says `live_install`,
wait for the new app's row to say `built:true` instead of a restart that never comes, still
restart once when the batch owes it, plan no "Restarting the orb" row when nothing restarts,
and makes the page's install/uninstall flows say what actually happened. An orb without
`live_install` keeps today's behaviour byte for byte (same plan, same lines, same requests).

## Read first

- `docs/app-platform-plan.md` §63 (line ~7915) — the owner's table of cases.
- `.delegate-specC.md` — the firmware contract: items 2 (live landing: the row is upserted
  unbuilt, then built and put on the glass on the LVGL task), 3 (uninstall moves to the next
  app), 5 (`restart_owed` keeps its meaning), 6 (the two new keys).
- `tools/orb-manager/internal/orbnet/apps.go` — `AppInstalledRow`, `AppList`, `Defers`, `Owes`:
  the pattern for the new fields and methods (doc comment above each, nil-safe receivers).
- `tools/orb-manager/installflow.go`:
  - `installPlan` (the plan rows: `check`, `send:<slug>`, `install:<slug>`, `restart`,
    seed rows `theme-send:<slug>` / `theme-check:<slug>` …), `seedSlug`, `themeSteps`;
  - `runPhases.phaseOf` (maps an action to its plan row);
  - `installRun` (the pre-plan theme read, the `Status`/`AppsList` opening reads, the seed
    before the apps when `phases.chooses`, `batch := len(slugs) > 1 && listing.Defers()`,
    `owed`, `restartOwed`, `sendOne`'s `landed`/`cycled`, the end-of-run `waited` logic and
    its `waitOrbCycle`);
  - `installOneApp` (the skip on an existing row, `needsCardBytes`/`cardHolds`, the card write,
    the queue loop with `AppInstallCard`/`AppInstallCardDeferred`, and the ledger poll with
    `silent`, the deferred `Owes` branch and the non-deferred row branch);
  - `h_libraryInstall` (the automatic `only=clock` arm: `waitOrbBack`, `parkGlass`,
    `verifySeededGlass`) — read only, it is not changed.
- `tools/orb-manager/installflow_test.go` — `TestTheRunSaysItsPlanFirst` (its `planIDs`
  helper calls `installPlan`), `TestAnInstallThatRodeTheRebootSaysSo`,
  `TestABatchRestartsTheOrbOnce` (the fake-orb shape to copy: `httptest.NewServer`, `newHub()`,
  `s.device`/`s.ota`/`s.orb` `.DevicePort = portOf(srv.URL)`, the shortened
  `installPoll`/`installRebootWait`/`cycleQuietGrace`/`installHard` vars restored by defer,
  shipped containers from `shippedLib`).
- `tools/orb-manager/library_test.go` — `TestInstallOneAppSkipsAnInstalledRow`, `portOf`.
- `tools/orb-manager/webui_test.go` — the source-pinning style for page tests (`os.ReadFile("web/app.js")`).
- `tools/orb-manager/web/app.js` — `updateEverything` (splices the hub plan under its `apps`
  row), `autoInstall` (the setup journey seed, splices the hub plan under `seed`),
  `streamInstall`, `streamSteps` (its final `frame.doing` line `"Done · the orb is back"`),
  `describeStep`, the Themes face's `appMissing` offer (~line 4588–4635).
- `tools/orb-manager/web/tabs.js` — `loadApps` (keeps the whole ledger in `appData`),
  `installButton`, `uninstallButton` (its confirm body), `removeFromCard`'s button (~line 2190).

## Contract

Files to modify, and nothing else:
`tools/orb-manager/internal/orbnet/apps.go`, `tools/orb-manager/installflow.go`,
`tools/orb-manager/installflow_test.go`, `tools/orb-manager/internal/orbnet/apps_test.go`
(create it if it does not exist; if a test file for apps.go already exists, add to that one),
`tools/orb-manager/webui_test.go`, `tools/orb-manager/web/app.js`, `tools/orb-manager/web/tabs.js`.

### 1. orbnet: the two facts (`internal/orbnet/apps.go`)

- `AppInstalledRow` gains, after `Failed`:
  ```go
  // Built is the row's init_done: its module is loaded and running this boot. Only firmware
  // that lands installs live sends it (AppList.LiveInstall); older firmware omits it.
  Built bool `json:"built,omitempty"`
  ```
- `AppList` gains, after `TryWhy`:
  ```go
  // LiveInstall says this firmware loads a NEW app at once, with no restart (§63); an
  // update of an app built this boot is still owed to a restart (RestartOwed).
  LiveInstall bool `json:"live_install,omitempty"`
  ```
- New methods, nil-safe like `Defers`:
  - `func (l *AppList) Live() bool` → `l != nil && l.LiveInstall`.
  - `func (l *AppList) BuiltRow(slug string) bool` → true when `l.Installed` has a row with
    `Slug == slug && Built && !Failed`; false for a nil list.

### 2. installflow.go

**a. New action word `"landed"`.** An `installStep` with `Action: "landed"` means "installed and
loaded live; on the dial; no restart owed". Add `"landed"` to the comment list on
`installStep.Action`. In `runPhases.phaseOf`, add `"landed"` to the case that returns
`"install:" + st.Step` (beside `"uploaded", "installing", "installed", "skipped"`).

**b. New func** (put it right after `installPlan`):
```go
// restartDue reports whether a run of slugs on this orb can end in a restart, so the plan
// lists the "restart" row only when it can (§63). An orb that does not land installs live,
// or a ledger that did not answer (nil), restarts as it always did. On a live orb only a
// replacement of an app already built this boot restarts it: a forced install over a built
// row, or a built row whose card copy is gone (installOneApp re-sends those bytes).
func restartDue(listing *orbnet.AppList, slugs []string, force bool) bool
```
Rules: `listing == nil || !listing.Live()` → `true`. Otherwise `true` iff some slug has an
`Installed` row with `Built` (failed or not does not matter here; use the row's `Built`) and
`force || (needsCardBytes(row) && !cardHolds(listing, slug))`. Else `false`.

**c. `installPlan` gains a last parameter `restarts bool`:**
```go
func installPlan(lib *Library, slugs []string, card, chooses bool, seeded map[string]bool, restarts bool) []planStep
```
When `restarts` is false the `{ID: "restart", Label: "Restarting the orb to load it", …}` row is
not appended. Nothing else in the plan changes. Update the doc comment with one sentence saying so.

**d. `installRun`:**
- Before the `send(installStep{… Action: "plan" …})` line, read the ledger once:
  `pre, _ := s.device.AppsList(ip)` (an error leaves `pre` nil and changes nothing). Compute
  `restarts := restartDue(pre, slugs, force && only != "")` and pass it to `installPlan`.
  The `force && only != ""` is the same value the loop passes to `installOneApp`.
- In `sendOne`, `"landed"` sets neither `landed` nor `cycled` (only `"installed"` does, as
  today). So a live landing is not owed (`owed` is not incremented) and does not make
  `rebooted` true; the end-of-run `waited := !rebooted || cycled` is then true and no
  `"restarting"` line or `waitOrbCycle` follows.
- The deferred batch stays: `batch := len(slugs) > 1 && listing.Defers()` and `?defer=1` on
  every install (the firmware lands a new app live even with defer, spec C item 2). The single
  `restartOwed` reboot runs only when `owed > 0`, i.e. when at least one install was owed.
- When `listing.Live()` and `restarts` is true and the run reaches its end with no reboot
  (`!rebooted`), send, just before `return seedErr`:
  `installStep{Step: "install", Action: "skipped", Phase: "restart", Note: "nothing to restart: the apps are on the dial"}`
  so the planned row reads skipped with a reason. Never send this line on an orb that is not
  `Live()` (old firmware's lines stay exactly as today).

**e. `installOneApp`:** after the existing skip block and before the card write, compute
```go
// §63: a NEW app on firmware that lands installs live is loaded at once; the hub waits for
// its row to say built, not for a restart. A replacement of a built app keeps today's wait.
fresh := listing.Live() && !listing.BuiltRow(slug)
```
(`fresh` must be decided from the ledger read at the top of `installOneApp`, before the
install is queued.) When `fresh`, the ledger poll (the `for {}` after `send(… "installing")`)
uses this branch instead of the deferred and non-deferred ones, for both values of `deferred`:
1. `err != nil` → `silent = true`, keep polling (as today).
2. `list.TryStem == slug && list.TryWhy != ""` → `return fmt.Errorf("the dial refused %s: %s", slug, list.TryWhy)`.
3. a card row `Stem == slug && !OK` → today's error `"the dial refused %s after the install: %s"`.
4. the installed row for `slug`:
   - `Failed` → `return fmt.Errorf("%s installed but did not load on the dial", slug)`;
   - `Built && silent` → the orb restarted anyway: send `installed` then
     `restarted` with Note `"the orb restarted to load it while it installed"` (today's two
     lines, so `sendOne` marks it cycled) and return nil;
   - `Built && !silent` → send `installStep{Step: slug, Action: "landed", Note: note}` where
     `note` is `"on the glass"` if `row.OnGlass` else `"in the carousel"`, and return nil;
   - present but not built → keep polling (the LVGL task has not built it yet).
5. Owed (`list.Owes(slug)`) on a fresh install → the firmware decided it needs a restart after
   all: send today's deferred line (`installed`, Note `"copied; the orb restarts once the rest are in"`)
   when `deferred`, return nil; when not deferred keep polling (the firmware reboots on its own and
   the row appears after the silence, case 4).
6. The `installWait`/`installHard` leash and its error text are unchanged.
When not `fresh`, the poll is exactly today's code.

### 3. The page

**`web/app.js`**
- `describeStep`: add `case "landed": return j.step + " is on the dial" + (j.note ? " (" + j.note + ")" : "");`
- `streamSteps`: collect the slugs of `"landed"` lines and whether any `"restarting"`,
  `"restarted"` or `"rebooting"` line arrived. The final `frame.doing` text on `ok` becomes
  `"Done · " + landedSlugs.join(", ") + " on the dial"` when at least one landed and nothing
  restarted; otherwise exactly today's `"Done · the orb is back"`. (Old firmware never sends
  `landed`, so its text is unchanged.)
- `updateEverything`, `autoInstall`: no code change. Their step lists splice the hub's plan,
  so the restart row is there exactly when `restartDue` says so. Do not touch them.
- Themes face `appMissing` offer (the block that calls
  `streamInstall(themeIP, appMissing, false, null, true, false, …)`): record whether a
  `j.action === "landed" && j.step === appMissing` line arrived in the existing onStep callback.
  On success write `aTitle + " is on the dial wearing this theme; re-reading the card"` when it
  landed, else today's `aTitle + " installed; re-reading the card"`.

**`web/tabs.js`**
- `installButton`: pass an `onStep` to `streamInstall` (7th argument) that records
  `j.action === "landed" && j.step === e.slug`. When the run was ok and it landed, `libVerdict.text`
  is `(e.title || e.slug) + " · installed — on the dial now, no restart"`; otherwise today's text.
- `uninstallButton`: when `appData && appData.live_install` and the row is on the glass, the
  confirm body is
  `(e.title || e.slug) + " is on the glass — the dial moves to the next app and erases the slot."`;
  otherwise today's body (`"…the dial will return to its menu and erase the slot."`) for an older
  orb, and the unchanged off-glass body.

## Behaviour and edge cases

| orb | run | requests | plan | lines |
|---|---|---|---|---|
| no `live_install` | anything | as today | as today (`restart` row) | as today |
| live | Install a new app (single, card or shelf) | upload, `POST /api/v1/apps/install?id=<slug>`, ledger polls; **no** `/api/v1/reboot` | no `restart` row | `<slug>/installing`, `<slug>/landed` (`on the glass`/`in the carousel`), `install/done`; no `restarting` |
| live | Update (force) of a built app, single | as today (firmware reboots itself) | `restart` row | as today |
| live | batch `a,b` (Update everything): `a` built, `b` new | both `?defer=1`; one `/api/v1/reboot` | one `restart` row | `a/installed` (owed), `b/landed`, then the restart as today |
| live | batch of only new apps | both `?defer=1`; **no** reboot | no `restart` row | each `landed` |
| live | non-forced install of a built app with its card copy | skip, as today | no `restart` row | `<slug>/skipped` |
| live | ledger read before the plan fails | — | `restart` row (as today) | if nothing restarts: `install/skipped` on `restart`, note `nothing to restart: the apps are on the dial` |
| live | new app that fails to load (`failed:true`) | no reboot | no `restart` row | `install/refused` with `<slug> installed but did not load on the dial` |
| live | theme seed before a new app (`phases.chooses`) | seed first, then install | seed rows, install, no `restart` | the app lands wearing its chosen theme (firmware reads the choice at init) |

- The join seed (`h_libraryInstall` automatic arm) is not changed. On a live orb the clock lands
  live and `parkGlass` normally answers `parked` (no reboot); if the face door does arm a boot,
  its existing `waitOrbCycle` handles it.
- Uninstall is the device's own door (`POST /api/v1/apps/uninstall`) and needs no hub change
  beyond the confirm copy; `loadApps` re-reads the ledger after it as today.

## Acceptance criteria

Run from `{home}/docker/Projects/gorb-os-2/tools/orb-manager`. Each must exit 0.

1. New tests exist and pass (each prints `--- PASS` for every name; a missing name prints
   `no tests to run`, which `grep -c` turns into a failure):
   ```
   bash -c 'set -o pipefail; go test -count=1 -v -run "^(TestALiveInstallLandsWithoutARestart|TestALiveBatchRestartsOnlyForUpdates|TestALiveLandingThatFailsSaysSo|TestRestartDue|TestThePageSaysALiveLanding)$" . 2>&1 | tee /tmp/d-new.log; test $(grep -c "^--- PASS" /tmp/d-new.log) -eq 5'
   ```
   and
   ```
   bash -c 'set -o pipefail; go test -count=1 -v -run "^TestAppListLiveFacts$" ./internal/orbnet/ 2>&1 | tee /tmp/d-orbnet.log; grep -q "^--- PASS: TestAppListLiveFacts" /tmp/d-orbnet.log'
   ```
   The tests:
   - `TestAppListLiveFacts` (orbnet): decode `{"mounted":true,"installed":[{"slug":"a","built":true},{"slug":"b","built":false},{"slug":"c","built":true,"failed":true}],"live_install":true}` →
     `Live()` true, `BuiltRow("a")` true, `BuiltRow("b")` false, `BuiltRow("c")` false,
     `BuiltRow("zz")` false; the same JSON without `live_install`/`built` → `Live()` false and
     every `BuiltRow` false; a nil `*AppList` → both false without a panic.
   - `TestRestartDue`: table — nil listing → true; not live → true; live, slug absent → false;
     live, built row, force → true; live, built row, no force, card holds it → false; live,
     built non-compiled row, no force, card copy absent → true; live, unbuilt row, force → false.
   - `TestALiveInstallLandsWithoutARestart`: fake orb at `installMinFW`-or-newer fw
     (`"v1.6.4+aaaaaaa"`), card already holding `color_picker` (`card=true`), ledger with no
     color_picker row until `/api/v1/apps/install`, then a row `built:false` for two polls, then
     `built:true,"on_glass":true`; the `/api/v1/sd` answer carries a card theme so no seed runs.
     Two cases in one test: **live** (`"live_install":true`): `installRun(… "color_picker", false, true, …)`
     returns nil; plan ids are exactly `check install:color_picker`; a step
     `color_picker/landed` with Phase `install:color_picker` and Note `on the glass`; no step has
     Action `restarting` or Phase `restart`; the fake saw zero `POST /api/v1/reboot`.
     **old** (no `live_install`, no `built`, row appears straight after the install): plan ids
     are exactly `check install:color_picker restart`; a `color_picker/installed` step; no
     `landed` step.
   - `TestALiveBatchRestartsOnlyForUpdates`: copy `TestABatchRestartsTheOrbOnce`'s shape
     (clock + weather from `shippedLib`, `t.Skipf` if absent), `"live_install":true`. Case 1:
     clock row `built:true`, no weather row; `installRun(… "clock,weather", true, false, …)`;
     installs `["clock+defer","weather+defer"]` (the fake owes clock on `defer=1` and adds a
     `built:true` weather row on its install); exactly one reboot; the plan contains `restart`;
     a `weather/landed` step. Case 2: neither installed; both land built; zero reboots; no
     `restart` in the plan; two `landed` steps.
   - `TestALiveLandingThatFailsSaysSo`: live fake; after the install the row reads
     `built:false,"failed":true`; `installOneApp(… "color_picker", nil, false, false, …)` on a
     card that holds it returns an error containing `did not load on the dial`, and the fake saw
     no reboot.
   - `TestThePageSaysALiveLanding` (webui_test.go, source pin): `web/app.js` contains
     `case "landed"` and `" on the dial"` in `streamSteps`'s done line; `web/tabs.js` contains
     `live_install` and `the dial moves to the next app`.
2. The existing tests that pin today's behaviour still pass unchanged in meaning (only the
   extra `true` argument added to `planIDs`'s `installPlan` call):
   ```
   bash -c 'set -o pipefail; go test -count=1 -v -run "^(TestTheRunSaysItsPlanFirst|TestABatchRestartsTheOrbOnce|TestAnInstallThatRodeTheRebootSaysSo|TestASeedGoesBeforeTheRestart|TestInstallOneAppSkipsAnInstalledRow)$" . 2>&1 | tee /tmp/d-old.log; test $(grep -c "^--- PASS" /tmp/d-old.log) -eq 5'
   ```
3. Whole suite, vet, the JS balance check and cross-builds:
   `bash -c 'set -o pipefail; make check 2>&1 | tee /tmp/d-check.log; grep -q "check: tests, vet, crosscheck and vendor-check all green" /tmp/d-check.log'`
   (takes ~5 minutes; the baseline on 2026-11-09 was all green, so any failure is this change's).
4. `gofmt -l internal/orbnet/apps.go installflow.go installflow_test.go webui_test.go` prints nothing.
5. `git -C {home}/docker/Projects/gorb-os-2 diff --stat -- main/ apps/ sdk/ docs/` shows
   no change made by you (compare with `git diff --stat` taken before you start; the tree
   already carries the owner's uncommitted work — leave every hunk of it alone).

## Bench on Gold (only if Gold runs step C's firmware)

Gold is `.orb-target`: ORB_IP {orb-ip}, MAC {orb-mac}, this clone's hub port 3780.
First `curl -s -m 8 http://{orb-ip}/api/v1/apps`. If it does not answer, or its JSON has no
`"live_install":true`, **skip the bench and say so** (`bench: skipped — Gold <not answering | has no live_install>`);
this step must not flash firmware.

If it does, you may only:
- Run a bench hub from your build: `go build -o /tmp/d-hub . && XDG_CONFIG_HOME={home}/docker/Projects/gorb-os-2/.hub-config nohup /tmp/d-hub -addr 127.0.0.1:3781 -only-orb {orb-mac} -no-autoinstall -library-apps <scratch copy of apps/> -library-themes <scratch copy of themes/> >/tmp/d-hub.log 2>&1 &`
  (scratch copies under your temp dir; never point it at the tree). Get the token:
  `curl -s -c /tmp/d-jar http://127.0.0.1:3781/ >/dev/null` and send the `orb_token` cookie value
  as `X-Orb-Token`. **Kill this hub before you finish** (it would block the owner's `make run`).
- Drive the hub: `POST /api/library/install?ip={orb-ip}&only=color_picker[&card=1]` and
  `…&only=clock&force=1`, reading the NDJSON whole.
- Drive the orb only through: `GET /api/v1/apps`, `GET /api/v1/status`, `GET /api/v1/log`,
  `GET /api/v1/screen?to=clock`, `POST /api/v1/apps/uninstall?id=color_picker`,
  and `GET /api/v1/fb?fmt=raw565&direct=1` (466×466 RGB565 LE at the end of the body; convert to PNG and look at it).
  No OTA, serial, esptool, erase, reset, re-provisioning, theme or card deletes.

Read `GET /api/v1/apps` first and note what is installed. Scenarios:
1. color_picker not installed (uninstall it if it is). Clock on the glass. Hub install of
   color_picker: the stream's plan has no `restart` row, a `color_picker/landed` line, `install/done`;
   `rst_name` and growing uptime in `/api/v1/status` show no reboot; the ledger row says
   `built:true`; the screenshot shows the color picker.
2. Hub `only=clock&force=1` (an update of a built app): the plan has `restart`, the orb restarts
   once, it comes back on its clock.
3. Leave Gold as found: the same apps installed (uninstall color_picker if it was not there at
   the start), the clock on the glass, the bench hub killed.
Report each scenario's plan ids, the lines that matter, and the screenshot paths.

## Out of scope

- Firmware (`main/`), apps (`apps/`, `sdk/`), docs, themes and the theme flows' own rows.
- `h_libraryInstall`, `parkGlass`, `verifySeededGlass`, `cleanSlate`: unchanged.
- `updateEverything` and `autoInstall`: no code change (they take the hub's plan).
- No new routes, no new hub flags, no restyling, no refactor of the ledger poll beyond the
  `fresh` branch.
- Do not commit; the orchestrator reviews and commits.

## Notes

- Decide `fresh` from the ledger read at the top of `installOneApp`, before the queue POST: after
  the install the firmware has already upserted an unbuilt row, so a later read cannot tell a new
  app from a failed rebuild.
- `restart_owed` (`Owes`) stays the only word for "waits on a restart"; a live landing is never in it.
- `landed` is deliberately a new action rather than `installed` with a note: `sendOne` counts
  `installed` as "this install reboots the orb" (`landed`/`owed`/`rebooted`), and a live landing
  must not count.
- The old-firmware fake rows carry no `built` key; `omitempty` + `Live()` keep every old path
  identical — that is what the `old` cases pin.
