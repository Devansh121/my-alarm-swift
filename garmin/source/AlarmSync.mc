import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// Watch side of the sync protocol (docs/garmin-sync-protocol.md).
//
// The state is one dictionary kept in Application.Storage:
//   "alarms"   the phone's last snapshot (wire alarms)
//   "outbox"   ops not yet acked by the phone, oldest first
//   "syncedAt" when the last snapshot arrived (epoch seconds), or null
//   "seq"      counter for op and alarm ids
//   "dev"      random per-install prefix for op and alarm ids
//
// Everything here is plain data in, plain data out, so it runs in the
// background service too and is unit tested without a phone.
(:background)
module AlarmSync {

    const VERSION = 1;
    const MAX_OUTBOX = 64;
    const STORAGE_KEY = "state";
    // "sk" value for a skip the phone hasn't confirmed yet.
    const SKIP_PENDING = -1;

    // ---- values from the wire ----

    // The SDK may deliver numbers as Number, Long, Float or Double.
    function num(value) as Number or Null {
        if (value instanceof Number) {
            return value;
        }
        if (value instanceof Long || value instanceof Float || value instanceof Double) {
            return value.toNumber();
        }
        return null;
    }

    // Booleans may arrive as 0/1.
    function bool(value) as Boolean or Null {
        if (value instanceof Boolean) {
            return value;
        }
        if (value instanceof Number) {
            return value != 0;
        }
        return null;
    }

    function isString(value, expected as String) as Boolean {
        return value instanceof String && value.equals(expected);
    }

    // ---- state ----

    function newState() as Dictionary {
        return {
            "alarms" => [],
            "outbox" => [],
            "syncedAt" => null,
            "seq" => 0,
            "dev" => null
        };
    }

    function load() as Dictionary {
        var stored = Storage.getValue(STORAGE_KEY);
        var state = newState();
        if (stored instanceof Dictionary) {
            if (stored["alarms"] instanceof Array) { state["alarms"] = stored["alarms"]; }
            if (stored["outbox"] instanceof Array) { state["outbox"] = stored["outbox"]; }
            state["syncedAt"] = num(stored["syncedAt"]);
            var seq = num(stored["seq"]);
            if (seq != null) { state["seq"] = seq; }
            if (stored["dev"] instanceof String) { state["dev"] = stored["dev"]; }
        }
        return state;
    }

    function save(state as Dictionary) as Void {
        Storage.setValue(STORAGE_KEY, state);
    }

    // ---- phone -> watch ----

    // Takes in a `snap` message: replaces the cached alarms and drops the
    // acked ops from the outbox. Returns false (and changes nothing) for
    // anything that isn't a snapshot this version understands.
    function applySnapshot(state as Dictionary, msg, now as Number) as Boolean {
        if (!(msg instanceof Dictionary) || !isString(msg["t"], "snap")) {
            return false;
        }
        var version = num(msg["v"]);
        var raw = msg["alarms"];
        if (version == null || version > VERSION || !(raw instanceof Array)) {
            return false;
        }
        var alarms = [];
        for (var i = 0; i < raw.size(); i++) {
            var alarm = cleanAlarm(raw[i]);
            if (alarm != null) {
                alarms.add(alarm);
            }
        }
        var ack = msg["ack"];
        if (ack instanceof Array && ack.size() > 0) {
            var outbox = state["outbox"] as Array;
            var kept = [];
            for (var i = 0; i < outbox.size(); i++) {
                if (!containsString(ack, outbox[i]["oid"])) {
                    kept.add(outbox[i]);
                }
            }
            state["outbox"] = kept;
        }
        state["alarms"] = alarms;
        state["syncedAt"] = now;
        return true;
    }

    // A wire alarm with known types only, or null if it has no usable id/time.
    function cleanAlarm(raw) as Dictionary or Null {
        if (!(raw instanceof Dictionary)) {
            return null;
        }
        var id = raw["id"];
        var h = num(raw["h"]);
        var m = num(raw["m"]);
        if (!(id instanceof String) || h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
            return null;
        }
        var days = [];
        var rawDays = raw["d"];
        if (rawDays instanceof Array) {
            for (var i = 0; i < rawDays.size(); i++) {
                var day = num(rawDays[i]);
                if (day != null && day >= 1 && day <= 7 && days.indexOf(day) < 0) {
                    days.add(day);
                }
            }
        }
        var label = raw["l"];
        var alarm = {
            "id" => id,
            "h" => h,
            "m" => m,
            "d" => sortNumbers(days),
            "l" => label instanceof String ? label : "Alarm",
            "e" => bool(raw["e"]) != false,
            "sn" => bool(raw["sn"]) != false,
            "sm" => num(raw["sm"]) != null ? num(raw["sm"]) : 9,
            "u" => num(raw["u"]) != null ? num(raw["u"]) : 0
        };
        var keys = ["nf", "sk", "sz"];
        for (var i = 0; i < keys.size(); i++) {
            var value = num(raw[keys[i]]);
            if (value != null) {
                alarm[keys[i]] = value;
            }
        }
        if (raw["ov"] instanceof Dictionary) {
            alarm["ov"] = raw["ov"];
        }
        return alarm;
    }

    // ---- watch -> phone ----

    // Queues an edit and returns it. `extra` adds "f" (put) or "e" (en).
    function addOp(state as Dictionary, kind as String, id as String, extra as Dictionary or Null,
                   now as Number) as Dictionary {
        var op = {
            "oid" => nextId(state, ""),
            "op" => kind,
            "id" => id,
            "at" => now
        };
        if (extra != null) {
            var keys = extra.keys();
            for (var i = 0; i < keys.size(); i++) {
                op[keys[i]] = extra[keys[i]];
            }
        }
        var outbox = state["outbox"] as Array;
        outbox.add(op);
        if (outbox.size() > MAX_OUTBOX) {
            outbox = outbox.slice(outbox.size() - MAX_OUTBOX, null);
        }
        state["outbox"] = outbox;
        return op;
    }

    // An id for a new alarm, unique to this watch.
    function newAlarmId(state as Dictionary) as String {
        return nextId(state, "w");
    }

    function syncMessage(state as Dictionary) as Dictionary {
        return {
            "t" => "sync",
            "v" => VERSION,
            "ops" => state["outbox"]
        };
    }

    function nextId(state as Dictionary, prefix as String) as String {
        if (state["dev"] == null) {
            Math.srand(System.getTimer());
            state["dev"] = (Math.rand() & 0xFFFFFF).format("%06x");
        }
        var seq = (state["seq"] as Number) + 1;
        state["seq"] = seq;
        return prefix + state["dev"] + "-" + seq;
    }

    // ---- the list the user sees ----

    // The snapshot with the outbox replayed on top. Alarms touched by an
    // unacked op carry "p" => true.
    function view(state as Dictionary) as Array {
        var alarms = state["alarms"] as Array;
        var list = [];
        for (var i = 0; i < alarms.size(); i++) {
            list.add(copy(alarms[i]));
        }
        var outbox = state["outbox"] as Array;
        for (var i = 0; i < outbox.size(); i++) {
            list = replay(list, outbox[i]);
        }
        return list;
    }

    function replay(list as Array, op as Dictionary) as Array {
        var index = indexOfId(list, op["id"]);
        var kind = op["op"];
        if (isString(kind, "put")) {
            var fields = op["f"] instanceof Dictionary ? op["f"] as Dictionary : {};
            if (index < 0) {
                if (num(fields["h"]) == null || num(fields["m"]) == null) {
                    return list;
                }
                var created = {
                    "id" => op["id"], "h" => 0, "m" => 0, "d" => [], "l" => "Alarm",
                    "e" => true, "sn" => true, "sm" => 9, "u" => 0
                };
                merge(created, fields);
                created["p"] = true;
                list.add(created);
            } else {
                merge(list[index], fields);
                list[index]["p"] = true;
            }
            return list;
        }
        if (index < 0) {
            return list;
        }
        var alarm = list[index] as Dictionary;
        if (isString(kind, "del")) {
            return list.slice(0, index).addAll(list.slice(index + 1, null));
        } else if (isString(kind, "en")) {
            var enabled = bool(op["e"]);
            if (enabled != null) {
                alarm["e"] = enabled;
                if (!enabled) {
                    alarm.remove("sz");
                    alarm.remove("sk");
                }
            }
        } else if (isString(kind, "skip")) {
            if ((alarm["d"] as Array).size() == 0) {
                alarm["e"] = false;
            } else if (alarm["e"]) {
                alarm["sk"] = SKIP_PENDING;
            }
        } else if (isString(kind, "unskip")) {
            alarm.remove("sk");
        } else {
            return list;
        }
        alarm["p"] = true;
        return list;
    }

    function find(list as Array, id) as Dictionary or Null {
        var index = indexOfId(list, id);
        return index < 0 ? null : list[index];
    }

    // ---- helpers ----

    function indexOfId(list as Array, id) as Number {
        for (var i = 0; i < list.size(); i++) {
            if (list[i]["id"] != null && id != null && list[i]["id"].equals(id)) {
                return i;
            }
        }
        return -1;
    }

    function containsString(list as Array, value) as Boolean {
        if (value == null) {
            return false;
        }
        for (var i = 0; i < list.size(); i++) {
            if (list[i] instanceof String && list[i].equals(value)) {
                return true;
            }
        }
        return false;
    }

    function copy(dict as Dictionary) as Dictionary {
        var out = {};
        merge(out, dict);
        return out;
    }

    function merge(target as Dictionary, source as Dictionary) as Void {
        var keys = source.keys();
        for (var i = 0; i < keys.size(); i++) {
            target[keys[i]] = source[keys[i]];
        }
    }

    function sortNumbers(values as Array) as Array {
        // Insertion sort: at most seven days.
        for (var i = 1; i < values.size(); i++) {
            var value = values[i];
            var j = i - 1;
            while (j >= 0 && values[j] > value) {
                values[j + 1] = values[j];
                j--;
            }
            values[j + 1] = value;
        }
        return values;
    }
}
