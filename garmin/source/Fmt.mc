import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Text for the alarm list and detail menus.
module Fmt {

    const DAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

    // "07:05" on a 24-hour watch, "7:05 AM" otherwise.
    function time(h as Number, m as Number, is24 as Boolean) as String {
        if (is24) {
            return h.format("%02d") + ":" + m.format("%02d");
        }
        var h12 = h % 12 == 0 ? 12 : h % 12;
        return h12 + ":" + m.format("%02d") + (h < 12 ? " AM" : " PM");
    }

    // ISO days (1 = Mon) as "Once", "Every day", "Weekdays", "Weekends"
    // or "Mon Wed Fri".
    function days(d as Array) as String {
        var sorted = AlarmSync.sortNumbers(d.slice(0, null));
        if (sorted.size() == 0) {
            return "Once";
        }
        if (sorted.size() == 7) {
            return "Every day";
        }
        if (sameDays(sorted, [1, 2, 3, 4, 5])) {
            return "Weekdays";
        }
        if (sameDays(sorted, [6, 7])) {
            return "Weekends";
        }
        var out = "";
        for (var i = 0; i < sorted.size(); i++) {
            out += (i > 0 ? " " : "") + DAY_NAMES[sorted[i] - 1];
        }
        return out;
    }

    function sameDays(a as Array, b as Array) as Boolean {
        if (a.size() != b.size()) {
            return false;
        }
        for (var i = 0; i < a.size(); i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }

    // The list row's second line, e.g. "Weekdays · Gym", "Off · Once",
    // "Skipping next · Weekdays", "Syncing · Once".
    function summary(alarm as Dictionary) as String {
        var parts = [];
        if (alarm["p"] == true) {
            parts.add("Syncing");
        }
        if (!alarm["e"]) {
            parts.add("Off");
        } else if (alarm["sz"] != null) {
            parts.add("Snoozed");
        } else if (alarm["sk"] != null) {
            parts.add("Skipping next");
        }
        parts.add(days(alarm["d"]));
        var label = alarm["l"];
        if (label instanceof String && !label.equals("Alarm") && label.length() > 0) {
            parts.add(label);
        }
        return join(parts, " · ");
    }

    function snooze(alarm as Dictionary) as String {
        return alarm["sn"] ? alarm["sm"] + " min" : "Off";
    }

    // Per-day times, e.g. "Fri 08:30, Sat 09:00", or null when none.
    function overrides(alarm as Dictionary, is24 as Boolean) as String or Null {
        var ov = alarm["ov"];
        if (!(ov instanceof Dictionary) || ov.size() == 0) {
            return null;
        }
        var parts = [];
        for (var day = 1; day <= 7; day++) {
            var hm = ov[day.toString()];
            if (hm instanceof Array && hm.size() == 2) {
                parts.add(DAY_NAMES[day - 1] + " " + time(hm[0], hm[1], is24));
            }
        }
        return parts.size() == 0 ? null : join(parts, ", ");
    }

    // "Mon 07:00" for an epoch time, in the watch's time zone.
    function moment(epoch as Number, is24 as Boolean) as String {
        var info = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_SHORT);
        // day_of_week: 1 = Sunday ... 7 = Saturday
        var iso = info.day_of_week == 1 ? 7 : info.day_of_week - 1;
        return DAY_NAMES[iso - 1] + " " + time(info.hour, info.min, is24);
    }

    // The sync row's second line.
    function syncStatus(syncedAt as Number or Null, now as Number, pending as Number,
                        phoneConnected as Boolean) as String {
        if (!phoneConnected) {
            return pending > 0 ? "Phone not connected · " + pending + " waiting" : "Phone not connected";
        }
        if (pending > 0) {
            return "Sending " + pending + (pending == 1 ? " change" : " changes");
        }
        if (syncedAt == null) {
            return "Open Alarm on your phone";
        }
        return "Synced " + ago(now - syncedAt);
    }

    function ago(seconds as Number) as String {
        if (seconds < 60) {
            return "just now";
        }
        if (seconds < 3600) {
            return (seconds / 60) + " min ago";
        }
        if (seconds < 86400) {
            return (seconds / 3600) + " h ago";
        }
        return (seconds / 86400) + " d ago";
    }

    function join(parts as Array, separator as String) as String {
        var out = "";
        for (var i = 0; i < parts.size(); i++) {
            out += (i > 0 ? separator : "") + parts[i];
        }
        return out;
    }
}
