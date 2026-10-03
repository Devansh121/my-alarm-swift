#!/usr/bin/env bash
# Build the Alarm watch app.
#
#   ./build.sh               compile bin/Alarm.prg for the Forerunner 965
#   ./build.sh run           build for the simulator (fake phone) and run it
#   ./build.sh test          build with unit tests and run them in the simulator
#   ./build.sh all           compile for every product in manifest.xml
#   ./build.sh package       export bin/Alarm.iq for the Connect IQ store
#
# Env: CIQ_SDK (SDK dir), CIQ_KEY (developer key), DEVICE (default fr965).
set -euo pipefail
cd "$(dirname "$0")"

DEVICE=${DEVICE:-fr965}
SDK=${CIQ_SDK:-$(ls -d ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-* 2>/dev/null | sort -V | tail -1)}
KEY=${CIQ_KEY:-$HOME/.Garmin/developer_key.der}

[ -x "$SDK/bin/monkeyc" ] || { echo "Connect IQ SDK not found, set CIQ_SDK" >&2; exit 1; }
[ -f "$KEY" ] || { echo "developer key $KEY not found, see README" >&2; exit 1; }
mkdir -p bin

# Starts the simulator if it isn't running. FRESH_SIM=1 restarts it with
# empty device state: a simulator whose /tmp state went stale (after killed
# runs) shows a blank error dialog and never loads an app.
simulator() {
    if [ "${FRESH_SIM:-0}" = 1 ]; then
        pkill -x simulator || true
        sleep 1
        local state="$PWD/bin/simstate"
        rm -rf "$state" && mkdir -p "$state"
        (cd "$SDK/bin" && TMPDIR="$state" exec ./simulator) </dev/null >/dev/null 2>&1 &
        sleep 7
    else
        pgrep -x simulator >/dev/null || { "$SDK/bin/connectiq" </dev/null >/dev/null 2>&1 & sleep 7; }
    fi
}

case "${1:-}" in
    # The simulator shows a blocking error on Communications.transmit (it
    # can only bridge to Android), so simulator builds use sim.jungle.
    test)
        "$SDK/bin/monkeyc" -d "$DEVICE" -f sim.jungle -o bin/Alarm-test.prg -y "$KEY" -t -w
        simulator
        exec "$SDK/bin/monkeydo" bin/Alarm-test.prg "$DEVICE" -t
        ;;
    run)
        "$SDK/bin/monkeyc" -d "$DEVICE" -f sim.jungle -o bin/Alarm-sim.prg -y "$KEY" -w
        simulator
        exec "$SDK/bin/monkeydo" bin/Alarm-sim.prg "$DEVICE"
        ;;
    all)
        for product in $(grep -o 'product id="[^"]*"' manifest.xml | cut -d'"' -f2); do
            echo "== $product"
            "$SDK/bin/monkeyc" -d "$product" -f monkey.jungle -o "bin/Alarm-$product.prg" -y "$KEY"
        done
        ;;
    package)
        exec "$SDK/bin/monkeyc" -e -f monkey.jungle -o bin/Alarm.iq -y "$KEY" -r
        ;;
esac

"$SDK/bin/monkeyc" -d "$DEVICE" -f monkey.jungle -o bin/Alarm.prg -y "$KEY" -w
