# Alarm for Garmin

A Connect IQ watch app that shows and edits the iOS app's alarms, kept in
sync both ways over Bluetooth. Protocol: [docs/garmin-sync-protocol.md](../docs/garmin-sync-protocol.md).

The phone still does all the ringing. The watch lists the alarms and edits
them: on/off, time, repeat days, label, snooze, skip next, delete, and add.
Tone, per-day times, gradual volume and vibrate-first are phone-only (per-day
times are shown on the watch).

Built for the Forerunner 965 and 19 other recent watches (see `manifest.xml`).

## Build

Needs the Connect IQ SDK (9.x, found under `~/.Garmin/ConnectIQ/Sdks`) and a
developer key (`~/.Garmin/developer_key.der`, or set `CIQ_KEY`):

```sh
openssl genrsa -out key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in key.pem -out ~/.Garmin/developer_key.der -nocrypt
```

```sh
./build.sh               # bin/Alarm.prg for the Forerunner 965 (DEVICE=... for another)
./build.sh all           # every product in manifest.xml
./build.sh test          # unit tests in the simulator
./build.sh run           # the app in the simulator, with a fake phone
./build.sh package       # bin/Alarm.iq for the Connect IQ store
```

## Install on a watch

Plug the watch in over USB and copy `bin/Alarm.prg` to `GARMIN/APPS/` on it
(Linux: the MTP mount under `/run/user/$UID/gvfs/`; macOS: OpenMTP or Android
File Transfer). Unplug, and "Alarm" appears in the watch's app list.

The iOS app finds the watch app by its id (`manifest.xml`, the same UUID as
`GarminConnection.watchAppId`). Keep them in step.

## Simulator

The simulator can't reach an iPhone (it only bridges to Android over adb),
and `Communications.transmit` there pops a blocking error dialog. So
`./build.sh run` and `./build.sh test` build with `sim.jungle`, which swaps
the radio for `FakePhone`: a stand-in that applies the watch's ops the way
the iOS app does and answers each sync with an acking snapshot. The
device build (`monkey.jungle`) leaves `FakePhone` out.

If the simulator shows a blank window and never loads an app (its device
state under `/tmp/com.garmin.connectiq` goes stale after killed runs), use
`FRESH_SIM=1 ./build.sh test`, which restarts it with empty state.

## Layout

| file | what |
|------|------|
| `source/AlarmSync.mc` | sync state, snapshots in, ops out, the list shown (background too) |
| `source/AlarmApp.mc` | app entry and the background service that stores snapshots |
| `source/Controller.mc` | foreground glue: sending, retrying, refreshing menus |
| `source/AlarmMenus.mc` | alarm list and alarm detail menus |
| `source/Editors.mc` | time picker, repeat, label, snooze editors |
| `source/Fmt.mc` | text for the menus |
| `source/FakePhone.mc` | simulator-only phone |
| `test/` | unit tests (`./build.sh test`) |
