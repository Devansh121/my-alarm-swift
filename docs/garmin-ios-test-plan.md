# Garmin sync: iOS test plan

What still needs testing on a Mac, an iPhone and a Garmin watch. The watch
side is already covered: 21 Monkey C unit tests and a full UI walk-through
in the Connect IQ simulator against a fake phone. The iOS sync logic has
unit tests that run in CI. What's left is the real Connect IQ SDK,
Bluetooth, and the two apps talking to each other.

Background: [garmin-sync-protocol.md](garmin-sync-protocol.md) (what goes
over the wire and who wins a conflict) and [garmin/README.md](../garmin/README.md)
(building and installing the watch app).

## Setup

You need:

- a Mac with Xcode 16+ and XcodeGen (`brew install xcodegen`)
- an iPhone on iOS 17+ with **Garmin Connect** installed and the watch
  (Forerunner 965, or another model listed in `garmin/manifest.xml`) paired to it
- the Connect IQ SDK 9.x on the Mac (SDK Manager:
  https://developer.garmin.com/connect-iq/sdk/) with the watch's device files,
  plus a developer key (see garmin/README.md); or a `bin/Alarm.prg` built elsewhere
- a USB cable for the watch, plus OpenMTP or Android File Transfer on the Mac

Steps:

1. Check out branch `feature/garmin-sync`.
2. Unit tests (expect 295 tests, 0 failures):
   ```sh
   xcodegen generate
   xcodebuild -project AlarmClock.xcodeproj -scheme AlarmClock \
     -destination 'platform=iOS Simulator,name=iPhone 16' test
   ```
   The new suites are `WatchWireTests`, `WatchSyncRulesTests`,
   `WatchSyncCoordinatorTests` and `WatchSyncFormattingTests`.
3. Build the watch app: `cd garmin && ./build.sh` (set `DEVICE=` if it isn't
   a Forerunner 965). Copy `garmin/bin/Alarm.prg` to `GARMIN/APPS/` on the
   watch, then unplug it. "Alarm" should show up in the watch's app list.
4. Open `AlarmClock.xcodeproj`, choose your team (the project uses
   `GBQ9HCSRG7`) and run on the iPhone. Swift Package Manager fetches
   `ConnectIQ` 1.8.0 from github.com/garmin/connectiq-companion-app-sdk-ios.
5. To see what the SDK is doing, open Console.app on the Mac, select the
   iPhone and filter by process `AlarmClock`. The Garmin Watch screen shows
   the last send error, if there was one.

For timing, "within seconds" means under 10 seconds with both devices
awake, close together and connected.

## Test cases

Note the result of each case (pass / fail / blocked). For a failure, note
what you saw and the Console output around it.

### A. Connecting

| # | Steps | Expected |
|---|-------|----------|
| A1 | Fresh install. Launch the app. | No Bluetooth permission prompt at launch. The alarm list has a new watch icon in the toolbar. |
| A2 | Tap the watch icon. | The "Garmin Watch" screen says no watch is connected; "Last watch sync" hint: "The watch syncs when you open Alarm on it." |
| A3 | Tap **Choose Garmin Watch**. | A Bluetooth permission prompt appears (allow it), then Garmin Connect opens its device picker. |
| A4 | Pick the watch in Garmin Connect and confirm. | You land back in Alarm (via the `alarmclock-ciq://` URL). The watch is listed as "Connecting…", then "Connected" within about 30 s. |
| A5 | Uninstall the watch app (or test before step 3 of setup), then reopen the screen. | "Connected · Alarm app not installed". |
| A6 | Force-quit the iPhone app and relaunch it. | The watch is still listed and reconnects without Garmin Connect. |
| A7 | Uninstall Garmin Connect (optional; skip if it would unpair the watch) and tap Choose. | The footer says Garmin Connect is needed. |

### B. Phone → watch

| # | Steps | Expected |
|---|-------|----------|
| B1 | Watch app open. Add an alarm on the phone (7:15, weekdays, label "Work"). | It appears on the watch within seconds: "7:15 AM · Weekdays · Work". |
| B2 | Watch app open. On the phone, toggle, edit and delete alarms. | The watch follows each change within seconds. |
| B3 | **Close** the watch app. Change an alarm on the phone. Wait 30 s, then open Alarm on the watch. | The change already shows when the list first appears (the background service stored it), before any round trip. |
| B4 | On the phone, set per-day times (Fri 8:30) on a repeating alarm. Open that alarm on the watch. | A "Per-day times" row shows "Fri 8:30 AM". Selecting it shows an "Edit on phone" toast. |
| B5 | Let a phone alarm ring and snooze it. | The watch row says "Snoozed". |
| B6 | Turn on Skip next on the phone. | The watch row says "Skipping next"; its detail shows "Cancel skip · Skipping <day time>". |

### C. Watch → phone (iPhone app open in the foreground)

For each case, check the phone's alarm list and, where relevant, the next
fire time. Make sure no edit shows "Syncing" on the watch for longer than a
few seconds.

| # | Watch action | Expected on phone |
|---|--------------|-------------------|
| C1 | Toggle Enabled off, then on | Toggle follows; a disabled alarm has no pending notifications |
| C2 | Time → 6:45 | Time changes and the alarm is rescheduled |
| C3 | Repeat → Weekdays / Weekends / Every day / Once | Days follow |
| C4 | Repeat → Custom → tick Mon, Wed, Fri → Back | Mon Wed Fri |
| C5 | Label → Gym; Label → Custom → type text → OK | Label follows (whitespace trimmed, cut at 40 characters) |
| C6 | Snooze → Off; Snooze → 15 min | Snooze off; snooze on, 15 min |
| C7 | Skip next on a repeating alarm, then Cancel skip | Skip shows, then clears |
| C8 | Skip next on a one-shot (only shown while on) | n/a: the watch only offers Skip on repeating alarms |
| C9 | Delete → Confirm | The alarm is gone and its notifications are cancelled |
| C10 | Add alarm → pick 5:30 AM | A new one-shot 5:30 alarm, on, label "Alarm", phone default tone |
| C11 | Make 5 quick edits to one alarm (toggle ×3, time, label) | The phone ends in the same state as the watch; the watch's Sync row ends at "Synced just now" |

### D. Phone app not in the foreground

| # | Steps | Expected |
|---|-------|----------|
| D1 | Background the iPhone app (home screen, don't force-quit). Edit an alarm on the watch. | Without opening the app, the change takes effect: check by opening the app later, or by the alarm ringing at the new time. Bluetooth background mode wakes the app. |
| D2 | Force-quit the iPhone app. Edit on the watch. | The watch keeps the edit and shows "Sending 1 change", then "Phone app not reachable" (iOS doesn't relaunch force-quit apps). Open the iPhone app: within about 60 s with the watch app open (or on the next watch edit or launch) the edit applies and the watch shows "Synced just now". |
| D3 | Reboot the iPhone, don't open the app, edit on the watch. | Note what happens. iOS may relaunch the app through Bluetooth state restoration. Either outcome is acceptable, but record which one. |
| D4 | Turn Bluetooth off on the iPhone, make two edits on the watch. | The watch Sync row: "Phone not connected · 2 waiting". Turn Bluetooth back on: the edits apply within about 60 s while the watch app is open. |

### E. Conflicts (last writer wins per alarm; read the protocol doc first)

| # | Steps | Expected |
|---|-------|----------|
| E1 | iPhone Bluetooth off. On the watch, set alarm X to 8:00. A minute later, on the phone, set X to 9:00. Bluetooth back on, open the watch app. | The phone edit is newer and wins: X stays 9:00, and the watch snaps back to 9:00. |
| E2 | iPhone Bluetooth off. On the phone, set X to 9:00. A minute later, on the watch, set X to 8:00. Bluetooth back on. | The watch edit is newer and wins: X becomes 8:00 on both. |
| E3 | iPhone Bluetooth off. On the watch, edit Y. Then delete Y on the phone. Reconnect. | Y stays deleted and disappears from the watch. |
| E4 | iPhone Bluetooth off. Delete Z on the phone. Then edit Z's time on the watch (it still shows Z). Reconnect. | The watch edit is newer than the delete, so Z comes back with the new time. This is by design; flag it if it feels wrong. |
| E5 | On the phone, give alarm W a pinned tone, per-day times, gradual volume off and vibrate-first on. Change W's time on the watch. | The time changes and every phone-only setting is unchanged. |

### F. Interplay with existing features

| # | Steps | Expected |
|---|-------|----------|
| F1 | Edit on the watch, then look at the home and lock screen widgets. | They show the new next alarm. |
| F2 | While an alarm is snoozed (Live Activity showing), turn it off on the watch. | The snooze ends, the Live Activity ends, and History records the morning as stopped. |
| F3 | Run "Test my alarm" on the phone. | The test alarm never shows on the watch. |
| F4 | A repeating alarm rings and you stop it on the phone. | The watch keeps it on and its next fire moves to the next day. A one-shot turns off on the watch too. |
| F5 | Garmin Watch screen → Disconnect → confirm. | The list empties; phone edits no longer reach the watch. Choose the watch again to reconnect. |
| F6 | Garmin Watch screen → Sync Now (watch connected). | Sends a snapshot; no visible change if already in sync. |

### G. Upgrade path

| # | Steps | Expected |
|---|-------|----------|
| G1 | Install the `master` build, create alarms, then install this branch over it. | Every alarm survives with all settings. The first watch sync shows them all. |

## Known limitations (by design for v1)

- The phone rings, not the watch. The watch buzzes through Garmin's normal
  phone-notification mirroring if that's enabled in Garmin Connect.
- Watch edits reach a **force-quit** iPhone app only after it's opened again
  (iOS won't relaunch it). The watch keeps them and retries.
- The watch retries unsent edits every 60 s only while the watch app is
  open; otherwise they go on the next launch or edit.
- Tone, per-day times, gradual volume and vibrate-first are phone-only.
- A watch with a badly wrong clock could win or lose conflicts it
  shouldn't. Garmin watches set their time from the phone, so this should
  not come up.

## Report format

```
Device: iPhone <model> iOS <ver>; watch <model> fw <ver>; branch commit <sha>
Unit tests: <n> passed / <n> failed
A1 pass | A2 pass | ... | E4 pass (note) | ...
Failures:
  <id>: <what happened> / <expected> / <Console excerpt>
```
