import Toybox.Lang;
import Toybox.WatchUi;

// Removes every item, so a menu can be refilled in place while open.
function clearMenu(menu as WatchUi.Menu2) as Void {
    while (menu.getItem(0) != null) {
        menu.deleteItem(0);
    }
}

// ---- the alarm list ----

class AlarmListMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => "Alarms"});
        rebuild();
    }

    function rebuild() as Void {
        clearMenu(self);
        var alarms = Controller.alarms();
        var is24 = Controller.is24();
        for (var i = 0; i < alarms.size(); i++) {
            var alarm = alarms[i];
            addItem(new WatchUi.MenuItem(Fmt.time(alarm["h"], alarm["m"], is24), Fmt.summary(alarm),
                                         alarm["id"], null));
        }
        addItem(new WatchUi.MenuItem("Add alarm", null, :add, null));
        var status = Fmt.syncStatus(Controller.state["syncedAt"], Controller.now(), Controller.pendingCount(),
                                    Controller.phoneConnected());
        if (Controller.lastSendFailed && Controller.phoneConnected()) {
            status = "Phone app not reachable";
        }
        addItem(new WatchUi.MenuItem("Sync now", status, :sync, null));
    }
}

class AlarmListDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :add) {
            TimePicker.push(7, 0, new Lang.Method(self, :onNewTime));
        } else if (id == :sync) {
            Controller.send();
            Controller.refresh();
        } else if (id instanceof String) {
            AlarmDetailMenu.push(id);
        }
    }

    function onNewTime(h as Number, m as Number) as Void {
        var id = Controller.create(h, m);
        AlarmDetailMenu.push(id);
    }
}

// ---- one alarm ----

class AlarmDetailMenu extends WatchUi.Menu2 {

    var alarmId as String;

    static function push(id as String) as Void {
        var menu = new AlarmDetailMenu(id);
        Controller.detailMenu = menu;
        WatchUi.pushView(menu, new AlarmDetailDelegate(id), WatchUi.SLIDE_LEFT);
    }

    function initialize(id as String) {
        alarmId = id;
        Menu2.initialize({:title => "Alarm"});
        rebuild();
    }

    function rebuild() as Void {
        clearMenu(self);
        var alarm = Controller.alarm(alarmId);
        if (alarm == null) {
            // Deleted here or on the phone.
            addItem(new WatchUi.MenuItem("Alarm deleted", null, :gone, null));
            return;
        }
        var is24 = Controller.is24();
        setTitle(Fmt.time(alarm["h"], alarm["m"], is24));
        addItem(new WatchUi.ToggleMenuItem("Enabled", alarm["p"] == true ? "Syncing" : null, :en,
                                           alarm["e"], null));
        addItem(new WatchUi.MenuItem("Time", Fmt.time(alarm["h"], alarm["m"], is24), :time, null));
        addItem(new WatchUi.MenuItem("Repeat", Fmt.days(alarm["d"]), :days, null));
        addItem(new WatchUi.MenuItem("Label", alarm["l"], :label, null));
        addItem(new WatchUi.MenuItem("Snooze", Fmt.snooze(alarm), :snooze, null));
        var ov = Fmt.overrides(alarm, is24);
        if (ov != null) {
            addItem(new WatchUi.MenuItem("Per-day times", ov + " (edit on phone)", :ov, null));
        }
        if (alarm["e"]) {
            if (alarm["sk"] != null) {
                var skipped = alarm["sk"] == AlarmSync.SKIP_PENDING ? "Syncing" : "Skipping " + Fmt.moment(alarm["sk"], is24);
                addItem(new WatchUi.MenuItem("Cancel skip", skipped, :unskip, null));
            } else if ((alarm["d"] as Array).size() > 0) {
                var next = alarm["nf"] != null && alarm["p"] != true ? "Next: " + Fmt.moment(alarm["nf"], is24) : null;
                addItem(new WatchUi.MenuItem("Skip next", next, :skip, null));
            }
        }
        addItem(new WatchUi.MenuItem("Delete", null, :del, null));
    }
}

class AlarmDetailDelegate extends WatchUi.Menu2InputDelegate {

    var alarmId as String;

    function initialize(id as String) {
        Menu2InputDelegate.initialize();
        alarmId = id;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var alarm = Controller.alarm(alarmId);
        var id = item.getId();
        if (alarm == null) {
            if (id == :gone) {
                onBack();
            }
            return;
        }
        if (id == :en) {
            Controller.edit("en", alarmId, {"e" => (item as WatchUi.ToggleMenuItem).isEnabled()});
        } else if (id == :time) {
            TimePicker.push(alarm["h"], alarm["m"], new Lang.Method(self, :onTime));
        } else if (id == :days) {
            RepeatMenu.push(alarmId, alarm["d"]);
        } else if (id == :label) {
            LabelMenu.push(alarmId);
        } else if (id == :snooze) {
            SnoozeMenu.push(alarmId, alarm);
        } else if (id == :skip) {
            Controller.edit("skip", alarmId, null);
        } else if (id == :unskip) {
            Controller.edit("unskip", alarmId, null);
        } else if (id == :del) {
            WatchUi.pushView(new WatchUi.Confirmation("Delete alarm?"), new DeleteDelegate(alarmId),
                             WatchUi.SLIDE_IMMEDIATE);
        }
    }

    function onTime(h as Number, m as Number) as Void {
        Controller.edit("put", alarmId, {"f" => {"h" => h, "m" => m}});
    }

    function onBack() as Void {
        Controller.detailMenu = null;
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class DeleteDelegate extends WatchUi.ConfirmationDelegate {

    var alarmId as String;

    function initialize(id as String) {
        ConfirmationDelegate.initialize();
        alarmId = id;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            Controller.edit("del", alarmId, null);
            // The confirmation closes itself; this closes the alarm's menu.
            Controller.detailMenu = null;
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
        return true;
    }
}
