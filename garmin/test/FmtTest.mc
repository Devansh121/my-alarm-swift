import Toybox.Lang;
import Toybox.Test;

(:test)
function testTime(logger as Test.Logger) as Boolean {
    Test.assertEqual(Fmt.time(7, 5, true), "07:05");
    Test.assertEqual(Fmt.time(19, 0, true), "19:00");
    Test.assertEqual(Fmt.time(0, 30, false), "12:30 AM");
    Test.assertEqual(Fmt.time(12, 0, false), "12:00 PM");
    Test.assertEqual(Fmt.time(19, 45, false), "7:45 PM");
    return true;
}

(:test)
function testDays(logger as Test.Logger) as Boolean {
    Test.assertEqual(Fmt.days([]), "Once");
    Test.assertEqual(Fmt.days([7, 1, 2, 3, 4, 5, 6]), "Every day");
    Test.assertEqual(Fmt.days([5, 4, 3, 2, 1]), "Weekdays");
    Test.assertEqual(Fmt.days([7, 6]), "Weekends");
    Test.assertEqual(Fmt.days([5, 1, 3]), "Mon Wed Fri");
    var d = [3, 1];
    Fmt.days(d);
    Test.assertEqual(d[0], 3);   // the caller's array isn't sorted in place
    return true;
}

(:test)
function testSummary(logger as Test.Logger) as Boolean {
    var alarm = {"d" => [1, 2, 3, 4, 5], "l" => "Gym", "e" => true};
    Test.assertEqual(Fmt.summary(alarm), "Weekdays · Gym");
    alarm["l"] = "Alarm";
    Test.assertEqual(Fmt.summary(alarm), "Weekdays");
    alarm["sk"] = 123;
    Test.assertEqual(Fmt.summary(alarm), "Skipping next · Weekdays");
    alarm["sz"] = 456;
    Test.assertEqual(Fmt.summary(alarm), "Snoozed · Weekdays");
    alarm["e"] = false;
    alarm["p"] = true;
    Test.assertEqual(Fmt.summary(alarm), "Syncing · Off · Weekdays");
    return true;
}

(:test)
function testSnoozeAndOverrides(logger as Test.Logger) as Boolean {
    Test.assertEqual(Fmt.snooze({"sn" => true, "sm" => 9}), "9 min");
    Test.assertEqual(Fmt.snooze({"sn" => false, "sm" => 9}), "Off");
    Test.assert(Fmt.overrides({}, true) == null);
    Test.assertEqual(Fmt.overrides({"ov" => {"6" => [9, 0], "5" => [8, 30]}}, true), "Fri 08:30, Sat 09:00");
    return true;
}

(:test)
function testSyncStatus(logger as Test.Logger) as Boolean {
    Test.assertEqual(Fmt.syncStatus(null, 100, 0, true), "Open Alarm on your phone");
    Test.assertEqual(Fmt.syncStatus(90, 100, 0, true), "Synced just now");
    Test.assertEqual(Fmt.syncStatus(100 - 600, 100, 0, true), "Synced 10 min ago");
    Test.assertEqual(Fmt.syncStatus(100 - 7200, 100, 0, true), "Synced 2 h ago");
    Test.assertEqual(Fmt.syncStatus(90, 100, 1, true), "Sending 1 change");
    Test.assertEqual(Fmt.syncStatus(90, 100, 3, true), "Sending 3 changes");
    Test.assertEqual(Fmt.syncStatus(90, 100, 0, false), "Phone not connected");
    Test.assertEqual(Fmt.syncStatus(90, 100, 2, false), "Phone not connected · 2 waiting");
    return true;
}

(:test)
function testMomentUsesIsoWeekday(logger as Test.Logger) as Boolean {
    // Whatever the simulator's time zone, the weekday and time agree with Gregorian.
    var text = Fmt.moment(1790000000, true);
    Test.assertEqual(text.length(), 9);
    var names = "Mon Tue Wed Thu Fri Sat Sun";
    Test.assert(names.find(text.substring(0, 3)) != null);
    return true;
}
