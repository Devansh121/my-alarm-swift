import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// ---- time ----

// Hour/minute picker, with an AM/PM column on 12-hour watches. Calls
// `done` with the 24-hour time.
module TimePicker {

    function push(h as Number, m as Number, done as Method) as Void {
        var is24 = Controller.is24();
        var picker;
        if (is24) {
            picker = new WatchUi.Picker({
                :title => new WatchUi.Text({:text => "Time", :color => Graphics.COLOR_WHITE,
                                            :locX => WatchUi.LAYOUT_HALIGN_CENTER, :locY => WatchUi.LAYOUT_VALIGN_BOTTOM}),
                :pattern => [new NumberFactory(0, 23, "%02d"), new NumberFactory(0, 59, "%02d")],
                :defaults => [h, m]
            });
        } else {
            var h12 = h % 12 == 0 ? 12 : h % 12;
            picker = new WatchUi.Picker({
                :title => new WatchUi.Text({:text => "Time", :color => Graphics.COLOR_WHITE,
                                            :locX => WatchUi.LAYOUT_HALIGN_CENTER, :locY => WatchUi.LAYOUT_VALIGN_BOTTOM}),
                :pattern => [new NumberFactory(1, 12, "%d"), new NumberFactory(0, 59, "%02d"), new AmPmFactory()],
                :defaults => [h12 - 1, m, h < 12 ? 0 : 1]
            });
        }
        WatchUi.pushView(picker, new TimePickerDelegate(is24, done), WatchUi.SLIDE_UP);
    }

    // The 24-hour time for picker values.
    function toHour(values as Array, is24 as Boolean) as Number {
        if (is24) {
            return values[0];
        }
        var h12 = values[0] % 12;
        return values[2] == 1 ? h12 + 12 : h12;
    }
}

class TimePickerDelegate extends WatchUi.PickerDelegate {

    var is24 as Boolean;
    var done as Method;

    function initialize(twentyFour as Boolean, callback as Method) {
        PickerDelegate.initialize();
        is24 = twentyFour;
        done = callback;
    }

    function onAccept(values as Array) as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        done.invoke(TimePicker.toHour(values, is24), values[1]);
        return true;
    }

    function onCancel() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

class NumberFactory extends WatchUi.PickerFactory {

    var first as Number;
    var last as Number;
    var pattern as String;

    function initialize(from as Number, to as Number, format as String) {
        PickerFactory.initialize();
        first = from;
        last = to;
        pattern = format;
    }

    function getSize() as Number {
        return last - first + 1;
    }

    function getValue(index as Number) as Object? {
        return first + index;
    }

    function getDrawable(index as Number, selected as Boolean) as Drawable? {
        return new WatchUi.Text({
            :text => (first + index).format(pattern),
            :color => Graphics.COLOR_WHITE,
            :font => Graphics.FONT_NUMBER_MEDIUM,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_CENTER
        });
    }
}

class AmPmFactory extends WatchUi.PickerFactory {

    function initialize() {
        PickerFactory.initialize();
    }

    function getSize() as Number {
        return 2;
    }

    function getValue(index as Number) as Object? {
        return index;
    }

    function getDrawable(index as Number, selected as Boolean) as Drawable? {
        return new WatchUi.Text({
            :text => index == 0 ? "AM" : "PM",
            :color => Graphics.COLOR_WHITE,
            :font => Graphics.FONT_MEDIUM,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_CENTER
        });
    }
}

// ---- repeat days ----

module RepeatMenu {

    const PRESETS = [
        ["Once", []],
        ["Every day", [1, 2, 3, 4, 5, 6, 7]],
        ["Weekdays", [1, 2, 3, 4, 5]],
        ["Weekends", [6, 7]]
    ];

    function push(alarmId as String, days as Array) as Void {
        var menu = new WatchUi.Menu2({:title => "Repeat"});
        var current = Fmt.days(days);
        for (var i = 0; i < PRESETS.size(); i++) {
            var name = PRESETS[i][0] as String;
            menu.addItem(new WatchUi.MenuItem(name, name.equals(current) ? "Current" : null, i, null));
        }
        menu.addItem(new WatchUi.MenuItem("Custom", current, :custom, null));
        WatchUi.pushView(menu, new RepeatDelegate(alarmId, days), WatchUi.SLIDE_LEFT);
    }
}

class RepeatDelegate extends WatchUi.Menu2InputDelegate {

    var alarmId as String;
    var days as Array;

    function initialize(id as String, current as Array) {
        Menu2InputDelegate.initialize();
        alarmId = id;
        days = current;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :custom) {
            var menu = new WatchUi.CheckboxMenu({:title => "Days"});
            for (var day = 1; day <= 7; day++) {
                menu.addItem(new WatchUi.CheckboxMenuItem(Fmt.DAY_NAMES[day - 1], null, day,
                                                          days.indexOf(day) >= 0, null));
            }
            // Replace this menu so Back from the days goes to the alarm.
            WatchUi.switchToView(menu, new CustomDaysDelegate(alarmId, menu), WatchUi.SLIDE_LEFT);
            return;
        }
        Controller.edit("put", alarmId, {"f" => {"d" => RepeatMenu.PRESETS[id as Number][1]}});
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class CustomDaysDelegate extends WatchUi.Menu2InputDelegate {

    var alarmId as String;
    var menu as WatchUi.CheckboxMenu;

    function initialize(id as String, checkboxes as WatchUi.CheckboxMenu) {
        Menu2InputDelegate.initialize();
        alarmId = id;
        menu = checkboxes;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        // Checkbox state is read when leaving.
    }

    // Leaving the list saves the ticked days.
    function onBack() as Void {
        var days = [];
        for (var i = 0; i < 7; i++) {
            var item = menu.getItem(i) as WatchUi.CheckboxMenuItem;
            if (item.isChecked()) {
                days.add(item.getId());
            }
        }
        Controller.edit("put", alarmId, {"f" => {"d" => days}});
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onDone() as Void {
        onBack();
    }
}

// ---- label ----

module LabelMenu {

    const PRESETS = ["Alarm", "Wake up", "Work", "Gym", "Run", "Nap", "Meds"];

    function push(alarmId as String) as Void {
        var menu = new WatchUi.Menu2({:title => "Label"});
        for (var i = 0; i < PRESETS.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(PRESETS[i], null, i, null));
        }
        if (WatchUi has :TextPicker) {
            menu.addItem(new WatchUi.MenuItem("Custom", null, :custom, null));
        }
        WatchUi.pushView(menu, new LabelDelegate(alarmId), WatchUi.SLIDE_LEFT);
    }
}

class LabelDelegate extends WatchUi.Menu2InputDelegate {

    var alarmId as String;

    function initialize(id as String) {
        Menu2InputDelegate.initialize();
        alarmId = id;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :custom) {
            var alarm = Controller.alarm(alarmId);
            var current = alarm != null ? alarm["l"] as String : "";
            WatchUi.switchToView(new WatchUi.TextPicker(current), new LabelTextDelegate(alarmId),
                                 WatchUi.SLIDE_LEFT);
            return;
        }
        Controller.edit("put", alarmId, {"f" => {"l" => LabelMenu.PRESETS[id as Number]}});
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class LabelTextDelegate extends WatchUi.TextPickerDelegate {

    var alarmId as String;

    function initialize(id as String) {
        TextPickerDelegate.initialize();
        alarmId = id;
    }

    function onTextEntered(text as String, changed as Boolean) as Boolean {
        if (changed && text.length() > 0) {
            Controller.edit("put", alarmId, {"f" => {"l" => text}});
        }
        return true;
    }

    function onCancel() as Boolean {
        return true;
    }
}

// ---- snooze ----

module SnoozeMenu {

    const MINUTES = [5, 9, 10, 15, 20, 30];

    function push(alarmId as String, alarm as Dictionary) as Void {
        var menu = new WatchUi.Menu2({:title => "Snooze"});
        menu.addItem(new WatchUi.MenuItem("Off", alarm["sn"] ? null : "Current", -1, null));
        for (var i = 0; i < MINUTES.size(); i++) {
            var current = alarm["sn"] && alarm["sm"] == MINUTES[i];
            menu.addItem(new WatchUi.MenuItem(MINUTES[i] + " min", current ? "Current" : null, MINUTES[i], null));
        }
        WatchUi.pushView(menu, new SnoozeDelegate(alarmId), WatchUi.SLIDE_LEFT);
    }
}

class SnoozeDelegate extends WatchUi.Menu2InputDelegate {

    var alarmId as String;

    function initialize(id as String) {
        Menu2InputDelegate.initialize();
        alarmId = id;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var minutes = item.getId() as Number;
        var fields = minutes < 0 ? {"sn" => false} : {"sn" => true, "sm" => minutes};
        Controller.edit("put", alarmId, {"f" => fields});
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
