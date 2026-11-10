# Hub step D: installs that land live — no restart for a new app, and the page says so

## Goal

Firmware step C (`.delegate-specC.md`, contract item 6) makes a NEW app land on the glass with
no reboot and says two new facts in `GET /api/v1/apps`: a top-level `"live_install":true` and a
per-`installed`-row `"built":true|false`. This step makes the hub and the page honour them:

- an install run on such firmware **waits for `built:true` instead of waiting for a restart**, and
  never asks the board to reboot for a new app it just landed live;
- a batch of new apps on such firmware sends its `?defer=1` installs and then finishes with **zero
  restarts** — today's run would sit in the poll until `installHard`, because a live landing is
  deliberately not in `restart_owed` (spec C item 5);
- the plan row and the panel's headline say what actually happens, so the operator never watches a
  hub wait for a restart that is never coming — the exact complaint §63's theme fix answered for
  stores (`storeNoRebootFW`, theme.go:1111, `TestAStoreOnlyRebootsOlderFirmware`);
- **an orb whose ledger says nothing about live installs keeps today's behaviour, unchanged**: same
  poll, same restart waits, same step words, same plan labels.

`web/tabs.js`'s post-run ledger re-read, the theme ladder and the uninstall proxy need no change;
Out of scope says why each is already right.

## Read first

1. `.delegate-specC.md` items 2, 5, 6 — the firmware contract you consume. Note especially: a NEW
   app lands live even when installed with `?defer=1` and **owes nothing**; only an install that
   replaced an app already built this boot owes or reboots.
2. `docs/app-platform-plan.md` §63 (line 7915) — the owner's rulings table; the Apps rows are what
   this step must not contradict.
3. `tools/orb-manager/installflow.go` — `installStep` (163), `planStep` (182), `runPhases`/`phaseOf`
   (193-226), `installPlan` (236-284), `installRun` (611-885: the `phases.chooses` seed order; the
   `batch`/`owed`/`restartOwed` block 745-757; `sendOne` with `landed`/`cycled` 793-818; the two
   restart waits 849-880), `installOneApp` (917-1113, poll loop 1058-1104), `installAppLive` (1272),
   `waitOrbCycle` (1724)/`waitOrbBack` (1777)/`beatFor`, and the timing constants 145-157.
4. `internal/orbnet/apps.go` — `AppInstalledRow` (55-90), `AppList` (120-136), `Defers()`/`Owes()`
   (139-152). `RestartOwed *[]string` is the house precedent for "a key old firmware never sends
   must not read as a false".
5. `internal/orbfake/apps.go` — `serveApps` (347), `installedJSONLocked` (394), `CardApp` (66);
   `internal/orbfake/orbfake.go:90-150` for the knob idiom (`Busy`, `Owed`, `NoDefer`, `BusyPolls`,
   `BusyForever`, `TearStore`, `UninstallSticks`) and `device.go:151` `Rebooted`.
6. `installflow_test.go` — `TestABatchRestartsTheOrbOnce` (582) is the shape of every test you add:
   scripted `httptest` ledger, the four timing constants shrunk and restored with a `defer`, and an
   assertion on the ordered installs the hub dialed. `TestTheCausedRebootsWaitOnTheCycle` (47) and
   `seedverify_test.go:328` `TestTheLadderIsPatientAcrossItsOwnReboots` are source-text gates naming
   exact strings in `installflow.go`; do not touch what they pin.
7. `web/app.js` — `streamSteps` (2258-2360; plan/skip/headline dispatch 2310-2334), `stepList` and
   `sl.skip(note)` (2224), `describeStep` (2361-2404); `web/tabs.js` — `installButton` (2006) and its
   post-run `loadApps()` retry (2033-2046).
8. `ui_test.go` — `readWebFile` and the text-gate style of `TestAppsFaceOffersThreeStatesAndNoToggle`
   (1520); `library_test.go`'s three `installOneApp` call sites (728, 804, 1026).
9. `.orb-target` — the bench binding this step is verified on.

## Contract

Files: `internal/orbnet/apps.go`, `installflow.go`, `internal/orbfake/apps.go`,
`internal/orbfake/orbfake.go`, `web/app.js`, and the tests (`installflow_test.go`, `ui_test.go`,
and `library_test.go` only if item 4 forces it). Nothing else. `theme.go`, `library.go`,
`web/tabs.js`, the routes and `security.go` do not change.

1. **The two facts, in the client** (`internal/orbnet/apps.go`, additive — no existing key moves).
   On `AppInstalledRow`, after `Version`:
   ```go
   Built *bool `json:"built,omitempty"`
   ```
   On `AppList`, after `RestartOwed`:
   ```go
   LiveInstall bool `json:"live_install,omitempty"`
   ```
   and two methods beside `Defers()` / `Owes()`:
   ```go
   // LandsLive reports whether this orb lands a new app with no restart (step C). The
   // ledger's word and not the hub's version table: an orb that says nothing is the
   // firmware that reboots, which is the reading that costs nothing.
   func (l *AppList) LandsLive() bool { return l != nil && l.LiveInstall }

   // IsBuilt reports the dial's own word that this row is loaded. It means nothing
   // unless LandsLive: an orb before step C omits the key, and Go reads an absent
   // *bool as nil and not as false.
   func (r AppInstalledRow) IsBuilt() bool { return r.Built != nil && *r.Built }
   ```
   `Built` is a `*bool` for `RestartOwed`'s stated reason: inventing `false` for a firmware that
   never answered would make every old-firmware row look unbuilt.

2. **`installOneApp` waits for the landing, not for the reboot** (`installflow.go:917`; signature
   UNCHANGED). After the listing read at the top, `live := listing.LandsLive()`. In the poll loop
   (1058-1104), whose `hard` stop is the `time.Now().After(hard)` arm at 1094:
    - **the non-deferred branch** (the `else if err == nil` arm at 1077, whose row loop today sends
      `"installed"` and returns): on live firmware a row found with `row.Built != nil && !row.IsBuilt()`
      is a copy that landed with the load still in flight — do **not** send `"installed"`, do **not**
      send `"restarted"` (the `silent` sub-step is a claim about a reboot that did not happen), keep
      polling, and say it once the way the busy wait says it once (the `told` idiom at 1025/1040):
      `send(installStep{Step: slug, Action: "installing", Note: "the orb is loading it on the glass"})`.
      When a later poll finds it `IsBuilt()`, that is the landing. A row found with no `built` key on
      live firmware (`row.Built == nil`) is a firmware that claimed live and cannot show its work:
      take the row as today.
    - **the deferred branch, live firmware** (1067-1076): landed when `list.Owes(slug)` — an update
      that really does owe, worded exactly as today — **or** when a row for the slug reports
      `IsBuilt()`, which is how a new app that landed live says so while spec C item 5 keeps it out of
      `restart_owed`. Today's arm reads only the owed list, so a live new app would sit here until
      `installHard`; the `TryStem`/`TryWhy` refusal below it must still win over the built wait.
   - every live landing is
     `send(installStep{Step: slug, Action: "loaded", Note: "the orb loaded it without a restart"})`
      — never `"installed"`, never `"restarted"`. `"installed"` is the step `sendOne` reads as "a
      slot was written, so this orb will reboot" (795-797, which sets `landed` and so `rebooted`),
      and a live landing must not set it.
   - **the timeout says the live truth**: a hard deadline that passes with the row present and
     unbuilt ends with
     `fmt.Errorf("%s copied but never loaded: the orb still says its row is not built — press Install again to check", slug)`,
     not today's "the copy may still be running".
   - no new timing constant: the existing `installWait` extension and `installHard` ceiling already
     bound a load, and a live load is seconds on a healthy board.

3. **`installRun` spends no wait on a restart that is not coming** (611-885). The ledger read that
   already gates `batch` is the one at 679 (re-read at 693), and `batch` is computed at 746: set
   `live := listing.LandsLive()` on the line after it, from that same listing.
   - `restartOwed` (748) is untouched: it no-ops when `owed == 0`, which is exactly the live-new-app
     case, and still boots a run that installed an update that owes.
   - the tail wait at 872-880 is reached only when `waited` is false, and `waited := !rebooted || cycled`
     (840) with `rebooted` set solely by `landed` from an `"installed"` step (795-797) — so item 2's
     `"loaded"` word is what keeps this wait off a live run. Say that in a comment there; it is the
     load-bearing inch of the change.
   - when the run ends with `live && !rebooted && owed == 0`, mark the plan's restart row skipped in
     the hub's own words instead of letting the page print its generic note:
     `send(installStep{Step: "install", Action: "skipped", Phase: "restart", Note: "no restart — the apps loaded as they landed"})`.
     `streamSteps` enters the phase from that line and then skips it (2320-2322), so one line does
     both.

4. **The plan row says which of the two it is** (`installPlan`, 236-284). Add one parameter, in the
   firmware-behaviour position beside its sibling flag:
   ```go
   func installPlan(lib *Library, slugs []string, card, chooses, live bool, seeded map[string]bool) []planStep
   ```
   The restart row keeps its `ID: "restart"`, `Kind: "wait"` and `Budget: restart` — the page splices
   and phases match on that id — and only its label changes: `"Restarting the orb to load it"` today,
   and `"The orb loads it without a restart"` when `live`. Call sites: `installRun` (651) passes the
   `live` from item 3, and `installflow_test.go:359` passes `false` for the new argument.

5. **`phaseOf` knows the new word** (210-226): add `"loaded"` to the
   `case "uploaded", "installing", "installed", "skipped":` arm, so a live landing is stamped into
   the `install:<slug>` phase and the panel advances the row it is really on.

6. **`web/app.js` — two lines, both in the shared step machinery.**
   - `describeStep` (2361): a case for the new action, note-first like `"restarted"` (2375):
     ```js
     case "loaded": return j.note || j.step + " loaded \u2014 no restart";
     ```
     (the file spells its em dashes `\u2014`, as the lines around it do)
   - `streamSteps` (2322): a skipped row's note comes from the hub when it has one, because
     "already there" is the wrong word for "nothing to restart":
     ```js
     sl.skip(j.note || (j.action === "skipped" ? "already there" : "not checked"));
     ```
   Nothing else in the page changes: plan rows, the bar, the clock and the splice are all
   hub-driven, and `tabs.js`'s post-run `loadApps()` (2033, with its 20 s second chance at 2042)
   already re-reads whatever the ledger says, whether or not the board rebooted to say it.

7. **`internal/orbfake` learns the two facts and the wait.** New on `Orb`, beside `Owed`/`NoDefer`
   and in the same comment idiom — a knob and not a query parameter, because no caller on the LAN
   can ask for that build, and a double you cannot drive into the awkward state never tests it:
   ```go
   // LiveInstall stands for firmware from step C: the ledger says live_install,
   // every installed row says built, and a NEW app lands with no restart.
   LiveInstall bool
   // BuiltPolls scripts the load still in flight: the next N GET /api/v1/apps
   // reads answer built:false for a row that landed live, decrementing on each,
   // and after them the row reports built:true. Zero is the healthy board.
   BuiltPolls int
   // BuiltForever scripts a load that never finishes, for the timeout's words.
   BuiltForever bool
   ```
    plus `Built bool` on `CardApp` (the row's load state, spelled with the file's own `tf()`).
   - `serveApps` (347): with `LiveInstall`, append `,"live_install":true` after the `try_why` pair on
     both the mounted and the unmounted answer, every existing key and its order kept — spec C item
     6 adds at the end for the same reason.
    - `installedJSONLocked` (394): with `LiveInstall`, every installed row carries `"built":` —
      spliced into the `tail` each arm already builds (400-416), so the identity tuple keeps its
      order — the built-in arm `true` (a compiled row was built at boot) and the card arm
      `tf(a.Built)`, the same way `failed`/`on_glass` are spelled at 421.
   - `serveAppInstall` (492): with `LiveInstall`, a NEW app — the row was not `Installed` or not
     `Built` before this call — comes back `Installed, Built = true, o.BuiltPolls <= 0` and is NOT
     appended to `Owed` even under `?defer=1`. An install of a row that was already `Built` (an
     update) is unchanged: `defer` owes it, no `defer` reboots. Each `/api/v1/apps` read decrements
     `BuiltPolls` and flips a pending row built, except under `BuiltForever`, which never flips.
   - `serveAppUninstall`, `serveReboot` (`device.go:899`, which clears `Owed`) and `UninstallSticks`
     keep their behaviour: a live uninstall is a firmware fact the hub only proxies.
8. **Tests.** In `installflow_test.go`'s existing style: a scripted ledger (or an `orbfake` double
   wired by `adopt_test.go`'s `fakeOrbServer`), the four timing constants (`installPoll`,
   `installRebootWait`, `cycleQuietGrace`, `installHard`) shrunk and restored with a `defer` as line
   583-585 does, and assertions on ordered facts — step words and reboot counts, never "no panic".
   Each must fail against the unfixed hub; name them as written.
   - `TestALiveInstallWaitsForTheRowBuilt` — live firmware, `BuiltPolls = 2`, one new slug: the steps
     carry an `installing` note about loading and then `loaded`, and carry no `installed` and no
     `restarting`; the plan's restart row is skipped with the hub's own note in it; the ledger was
     dialed more than once after the install POST.
   - `TestALiveBatchRestartsNothing` — two new slugs on live firmware, both installs out with
     `defer=1`: neither ever appears in `restart_owed`, `POST /api/v1/reboot` is dialed zero times,
     and no step of action `restarting` or `restarted` appears. Assert the ordered install list the
     way `TestABatchRestartsTheOrbOnce` does, so the deferred query itself stays proven.
   - `TestALiveLandingThatNeverBuildsNamesItsRow` — `BuiltForever`: the run refuses, and the refusal
     sentence names the slug and says it never loaded.
   - `TestAnUpdateOnLiveFirmwareStillOwesItsRestart` — live firmware, `defer`, a row already built:
     the run restarts exactly once and the step still says "copied; the orb restarts once the rest
     are in".
   - `TestOldFirmwareSawNoChange` — `LiveInstall` false, one new slug: the steps still carry
     `installed`, the run still dials exactly one reboot and waits the cycle, and the plan's restart
     row still reads "Restarting the orb to load it". This is the regression gate for the whole step;
     it must pass before item 2 is written as well as after.
   - `TestAPlanOnLiveFirmwareSaysNoRestart` — `installPlan(…, live=true)`: the `ID == "restart"` row
     is labelled "The orb loads it without a restart", keeps `Kind: "wait"` and `Budget > 0`, and the
     row count equals the `live=false` count — the row is relabelled, not dropped, so "step 3 of 7"
     stays true on both firmwares.
   - `ui_test.go`: `TestInstallStepsWordALiveLanding` — the text-gate style of `readWebFile`:
     `describeStep` has a `"loaded"` case, and the `sl.skip(` call inside `streamSteps` passes
     `j.note`.

## Behaviour and edge cases

- **The gate is the ledger's word, never a version constant.** Do not add a `liveInstallFW`: the
  hub asks the orb. An orb that answers no `live_install` gets today's run, and that includes an
  orb whose `/api/v1/apps` read fails — item 2 decides from the listing `installOneApp` already read
  before it touched anything, and a listing it could not read is not a claim of live landing.
- **A run that mixes new apps and updates** on live firmware: each new app says `loaded` with no
  restart of its own, each update goes into `restart_owed`, and `restartOwed` boots the run once at
  the end for the updates. `owed > 0` must suppress item 3's skip line — the restart really is owed.
- **A run of new apps only, non-deferred** (a single Install press): the poll's non-deferred branch
  waits the built flag and the run says no restart line at all.
- **The join-time seed** (`autoInstall`, app.js 1905, and the `only=clock` run it drives): the
  pre-app theme seed is already gated by `phases.chooses` (installflow.go 724) and does not change; on
  live firmware the clock install lands live, the plan shows the relabelled row skipped, and
  `releaseSeed` prints the run's own verdict — the page's seed path contains no restart text of its
  own, so nothing there needs a second story.
- **Update everything** (app.js 1216's `apps` row): unchanged; it splices the hub's plan under its
  `apps:` prefix, so the relabel and the skip ride through it for free. Verify it by reading the
  splice, not by changing it.
- **A card-only Install press** (`card=1`, an empty blob): item 2 applies as it does to any install —
  the landing is the same landing.
- **A live install of an app whose row the dial later refuses** (the ladder's gates, `TryStem`/`!OK`):
  today's two refusals still fire and win over the built wait. Do not swallow them into the wait.
- **A refused card write** still retries `cardWriteTries` times before any of this.
- **No theme change, no uninstall change, no new route, no new query, no new constant, no new
  dependency.**

## Acceptance criteria

1. `bash -c 'set -o pipefail; cd {home}/docker/Projects/gorb-os-2/tools/orb-manager && make check 2>&1 | tail -25'`
   → exit 0 and the line `check: tests, vet, crosscheck and vendor-check all green`. (`make test`
   alone is not enough: `vet` catches the new `installPlan` arity.)
2. `bash -c 'set -o pipefail; cd {home}/docker/Projects/gorb-os-2/tools/orb-manager && go test -count=1 -v -run "LiveInstall|LiveBatch|LiveLanding|LiveFirmware|OldFirmware|PlanOnLive" . 2>&1 | tail -30'`
   → every test named in contract item 8 ran, zero `--- FAIL` lines, and the run lists at least six
   tests. Quote the list.
3. The old suite is untouched where it pins the old behaviour: `TestABatchRestartsTheOrbOnce`, the
   reboot-riding test at line 394, `TestTheCausedRebootsWaitOnTheCycle`,
   `TestAStoreOnlyRebootsOlderFirmware` and `TestTheLadderIsPatientAcrossItsOwnReboots` pass
   **unmodified** — quote `git diff --stat` over the test files and show those five names absent from
   it, or name the one line of one of them you had to touch and why.
4. `grep -rn "live_install\|LandsLive\|IsBuilt\|\"loaded\"" tools/orb-manager/installflow.go tools/orb-manager/internal/orbnet/apps.go`
   → the client field, the two methods, the `loaded` step and its `phaseOf` arm are all present; and
   `grep -rn "liveInstallFW" tools/orb-manager` → no hits, i.e. no version-string gate was invented.
5. In the report: the NDJSON the hub streamed for (a) one new install and (b) a two-app deferred
   batch on live firmware, as a test captured them — the actual step lines in order.

## Out of scope

- **Firmware** — anything under `main/`. Step C owns it; this step is the consumer.
- **Themes** — `theme.go`'s store ladder (`storeNoRebootFW`, `removeNoRebootFW`, `waitForStore`,
  `themeSteps`) already picks its waits by firmware floor; an app landing is not a store.
- **Uninstall** — the hub only proxies `POST /api/v1/apps/uninstall` (`security.go:415`,
  `orbnet.AppUninstall`, `tabs.js:2075` and `2210`); spec C items 3-4 make the dial move on and free
  the engine, and the face already re-reads the ledger after the press. A hub change there would put
  a second authority on a fact the dial now answers.
- **An `installed · not loaded yet` chip** on the Apps face for a row reporting `built:false`: the
  window is a second wide on a healthy board, `appStateSentence` (tabs.js 1838) is crowded, and the
  run's own step already says it. The orchestrator's call, not this step's.
- The editor bridge, `contract_test.go`'s fixture (no route the editor uses changes), `seed.go`, the
  join-time shelf gate, and the join dialog's copy.

## Bench on Gold (required: this step is not done until these pass on the real orb)

Gold is this clone's bound orb (`.orb-target`): `ORB_LABEL=orb-B`, `ORB_IP={orb-ip}`, base MAC
`{orb-mac}`, and this clone's hub listens on `ORB_HUB_PORT=3780`. Start it with
`make run ARGS=--no-window` (the port and the `-only-orb` gate come from `.orb-target`) and stop it
by the pid you recorded. A scripted POST needs this launch's token:
`TOKEN=$(curl -s http://127.0.0.1:3780/ | sed -n 's/.*window\.__ORB_TOKEN__ = "\(.*\)".*/\1/p')` then
`-H "X-Orb-Token: $TOKEN"` (README's scripted path, on this clone's port). The glass:
`curl -s "http://{orb-ip}/api/v1/fb?fmt=raw565&direct=1" -o fb.raw` is 466x466 RGB565
little-endian; convert with Python and LOOK at it, saving each PNG to the evidence dir. The panel's
own words: `make cdp EXPR='...'` reads the live page's DOM (`tools/orb-manager/scripts/orb_cdp.py`);
quote that text — it is stronger evidence than a screenshot of a list.

Step C's firmware must be on the board; `GET /api/v1/apps` answering `"live_install":true` is the
proof, and the scenarios do not run without it. Read `GET /api/v1/apps` before each scenario, note
what is installed, and put it back after. Apps to add and remove: the shelf's
`color_picker.orbapp` and `radar.orbapp` (`tools/orb-manager/apps/`).

1. **A new app lands live with no restart.** Uninstall color_picker first if it is installed. Run the
   install through the hub (`POST /api/library/install?ip={orb-ip}&only=color_picker&force=1`,
   read it with `-N` so the NDJSON shows, or press the Apps face's Install). Record: the streamed step
   lines in order; a `loaded` step and no `installed`/`restarting` step for that slug; the run's
   `skipped` line carrying phase `restart` and the hub's note; `GET /api/v1/status` before and after
   with `rst_name` unchanged and the board never silent; `GET /api/v1/apps` showing color_picker
   `built:true`; and the glass showing color_picker (PNG).
2. **Two new apps, one run, zero restarts.** The same door with `only=color_picker,radar`: both land
   `loaded`, no `POST /api/v1/reboot` is dialed at all, the panel's restart row shows
   "no restart — the apps loaded as they landed", and `GET /api/v1/log` carries both landings.
3. **An update still restarts, exactly once.** With color_picker installed and running, press Update
   (force, the shelf's bytes over the running app): the orb restarts once, comes back, and the panel
   says the restart in today's words. Spec C keeps this case owed; the hub must not improve it away.
4. **Old firmware saw no change.** If a second orb on the bench answers `GET /api/v1/apps` with no
   `live_install`, run scenario 1's install there and record today's `installed` + `restarting` + one
   reboot. If no such orb exists, say so plainly and record instead the item-8 `LiveInstall`-false
   test's captured steps and `TestABatchRestartsTheOrbOnce` passing — do not fake an old board and do
   not downgrade Gold's firmware.
5. **Leave Gold as you found it**: the same apps installed, the clock on the glass, the same firmware
   stamp (name the stamp).

If the card refuses a write ("the card refused the write") the hub retries it itself
(`cardWriteTries`); if it then answers "no card in the socket", STOP and report `blocked` — that card
needs a power cycle, which is not yours to cause.

## Notes

- Do not commit; the orchestrator reviews and commits.
- `installflow.go`'s comments carry their bench history, and every step word here reaches an operator.
  Keep the voice: say what the orb is doing, name the release and the date where you change what the
  run waits for, and write no comment that restates the line above it.
- If step C's keys arrive named other than `live_install` / `built`, follow the firmware — it is
  ground truth, and this spec's intent is the wait and not the spelling — and record the spelling you
  consumed.


