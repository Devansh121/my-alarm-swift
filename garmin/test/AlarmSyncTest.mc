import Toybox.Lang;
import Toybox.Test;

// The sync core: snapshots in, ops out, and the list shown in between.

(:test)
module SyncFixtures {
    // A snapshot as the iOS app sends it (see WatchWireTests).
    function snap(ack as Array) as Dictionary {
        return {
            "t" => "snap", "v" => 1, "ts" => 1790000000, "ack" => ack,
            "alarms" => [
                {"id" => "a1", "h" => 7, "m" => 0, "d" => [5, 1, 2, 3, 4], "l" => "Work", "e" => true,
                 "sn" => true, "sm" => 9, "u" => 1789990000, "nf" => 1790020000},
                {"id" => "a2", "h" => 9, "m" => 30, "d" => [], "l" => "Alarm", "e" => false,
                 "sn" => false, "sm" => 5, "u" => 0, "ov" => {"5" => [8, 30]}}
            ]
        };
    }
}

(:test)
function testSnapshotReplacesAlarms(logger as Test.Logger) as Boolean {
    var state = AlarmSync.newState();
    Test.assert(AlarmSync.applySnapshot(state, SyncFixtures.snap([]), 100));
    var alarms = state["alarms"] as Array;
    Test.assertEqual(alarms.size(), 2);
    Test.assertEqual(alarms[0]["id"], "a1");
    Test.assertEqual(alarms[0]["d"].toString(), [1, 2, 3, 4, 5].toString());
    Test.assertEqual(alarms[0]["nf"], 1790020000);
    Test.assertEqual(alarms[1]["e"], false);
    Test.assertEqual(alarms[1]["ov"]["5"][1], 30);
    Test.assertEqual(state["syncedAt"], 100);
    return true;
}

(:test)
function testSnapshotIgnoresOtherMessages(logger as Test.Logger) as Boolean {
    var state = AlarmSync.newState();
    Test.assert(!AlarmSync.applySnapshot(state, "hello", 1));
    Test.assert(!AlarmSync.applySnapshot(state, {"t" => "sync", "v" => 1, "alarms" => []}, 1));
    Test.assert(!AlarmSync.applySnapshot(state, {"t" => "snap", "v" => 2, "alarms" => []}, 1));
    Test.assert(!AlarmSync.applySnapshot(state, {"t" => "snap", "v" => 1}, 1));
    Test.assert(state["syncedAt"] == null);
    return true;
}

(:test)
function testSnapshotDropsBadAlarmsAndCoercesTypes(logger as Test.Logger) as Boolean {
    var state = AlarmSync.newState();
    var msg = {"t" => "snap", "v" => 1l, "alarms" => [
        {"id" => "ok", "h" => 6l, "m" => 15.0, "d" => [3, 9, 3], "e" => 1, "sn" => 0},
        {"id" => "bad", "h" => 24, "m" => 0},
        {"h" => 7, "m" => 0},
        "junk"
    ]};
    Test.assert(AlarmSync.applySnapshot(state, msg, 1));
    var alarms = state["alarms"] as Array;
    Test.assertEqual(alarms.size(), 1);
    Test.assertEqual(alarms[0]["h"], 6);
    Test.assertEqual(alarms[0]["m"], 15);
    Test.assertEqual(alarms[0]["d"].toString(), [3].toString());
    Test.assertEqual(alarms[0]["e"], true);
    Test.assertEqual(alarms[0]["sn"], false);
    Test.assertEqual(alarms[0]["l"], "Alarm");
    Test.assertEqual(alarms[0]["sm"], 9);
    return true;
}

(:test)
function testOpsGetUniqueIdsAndFormASyncMessage(logger as Test.Logger) as Boolean {
    var state = AlarmSync.newState();
    var a = AlarmSync.addOp(state, "en", "a1", {"e" => false}, 500);
    var b = AlarmSync.addOp(state, "del", "a2", null, 501);
    Test.assert(!a["oid"].equals(b["oid"]));
    Test.assertEqual(a["op"], "en");
    Test.assertEqual(a["e"], false);
    Test.assertEqual(a["at"], 500);
    var id = AlarmSync.newAlarmId(state);
    Test.assert(id.substring(0, 1).equals("w"));
    var msg = AlarmSync.syncMessage(state);
    Test.assertEqual(msg["t"], "sync");
    Test.assertEqual(msg["v"], 1);
    Test.assertEqual((msg["ops"] as Array).size(), 2);
    return true;
}

(:test)
function testOutboxIsCapped(logger as Test.Logger) as Boolean {
    var state = AlarmSync.newState();
    for (var i = 0; i < AlarmSync.MAX_OUTBOX + 5; i++) {
        AlarmSync.addOp(state, "en", "a1", {"e" => true}, i);
    }
    var outbox = state["outbox"] as Array;
    Test.assertEqual(outbox.size(), AlarmSync.MAX_OUTBOX);
    Test.assertEqual(outbox[0]["at"], 5);
    return true;
}

(:test)
function testAckDropsOnlyAckedOps(logger as Test.Logger) as Boolean {
    var state = AlarmSync.newState();
    var a = AlarmSync.addOp(state, "en", "a1", {"e" => false}, 1);
    var b = AlarmSync.addOp(state, "del", "a2", null, 2);
    AlarmSync.applySnapshot(state, SyncFixtures.snap([a["oid"], "unknown"]), 3);
    var outbox = state["outbox"] as Array;
    Test.assertEqual(outbox.size(), 1);
    Test.assertEqual(outbox[0]["oid"], b["oid"]);
    return true;
}

(:test)
function testViewReplaysPendingEdits(logger as Test.Logger) as Boolean {
    var state = AlarmSync.newState();
    AlarmSync.applySnapshot(state, SyncFixtures.snap([]), 1);
    AlarmSync.addOp(state, "put", "a1", {"f" => {"h" => 6, "l" => "Gym"}}, 2);
    AlarmSync.addOp(state, "del", "a2", null, 3);
    AlarmSync.addOp(state, "put", "w1", {"f" => {"h" => 5, "m" => 45, "d" => []}}, 4);
    var list = AlarmSync.view(state);
    Test.assertEqual(list.size(), 2);
    Test.assertEqual(list[0]["id"], "a1");
    Test.assertEqual(list[0]["h"], 6);
    Test.assertEqual(list[0]["m"], 0);
    Test.assertEqual(list[0]["l"], "Gym");
    Test.assertEqual(list[0]["p"], true);
    Test.assertEqual(list[1]["id"], "w1");
    Test.assertEqual(list[1]["e"], true);
    Test.assertEqual(list[1]["sm"], 9);
    // The cached snapshot itself is untouched.
    Test.assertEqual((state["alarms"] as Array)[0]["h"], 7);
    Test.assert((state["alarms"] as Array)[0]["p"] == null);
    return true;
}

(:test)
function testViewToggleAndSkip(logger as Test.Logger) as Boolean {
    var state = AlarmSync.newState();
    AlarmSync.applySnapshot(state, SyncFixtures.snap([]), 1);
    AlarmSync.addOp(state, "skip", "a1", null, 2);
    AlarmSync.addOp(state, "en", "a2", {"e" => true}, 3);
    var list = AlarmSync.view(state);
    Test.assertEqual(list[0]["sk"], AlarmSync.SKIP_PENDING);
    Test.assertEqual(list[1]["e"], true);

    AlarmSync.addOp(state, "unskip", "a1", null, 4);
    AlarmSync.addOp(state, "skip", "a2", null, 5);    // a one-shot: skipping turns it off
    list = AlarmSync.view(state);
    Test.assert(list[0]["sk"] == null);
    Test.assertEqual(list[1]["e"], false);
    return true;
}

(:test)
function testTurningOffClearsSnoozeAndSkip(logger as Test.Logger) as Boolean {
    var state = AlarmSync.newState();
    var msg = SyncFixtures.snap([]);
    msg["alarms"][0]["sz"] = 1790000600;
    msg["alarms"][0]["sk"] = 1790020000;
    AlarmSync.applySnapshot(state, msg, 1);
    AlarmSync.addOp(state, "en", "a1", {"e" => false}, 2);
    var alarm = AlarmSync.view(state)[0];
    Test.assert(alarm["sz"] == null);
    Test.assert(alarm["sk"] == null);
    return true;
}

(:test)
function testOpsOnMissingAlarmsAreIgnoredInView(logger as Test.Logger) as Boolean {
    var state = AlarmSync.newState();
    AlarmSync.applySnapshot(state, SyncFixtures.snap([]), 1);
    AlarmSync.addOp(state, "en", "gone", {"e" => false}, 2);
    AlarmSync.addOp(state, "put", "gone2", {"f" => {"l" => "No time"}}, 3);
    Test.assertEqual(AlarmSync.view(state).size(), 2);
    return true;
}

(:test)
function testPhoneStateWinsOnceAcked(logger as Test.Logger) as Boolean {
    // The phone rejected a stale edit: it acks it and its snapshot is the truth.
    var state = AlarmSync.newState();
    AlarmSync.applySnapshot(state, SyncFixtures.snap([]), 1);
    var op = AlarmSync.addOp(state, "put", "a1", {"f" => {"h" => 11}}, 2);
    Test.assertEqual(AlarmSync.view(state)[0]["h"], 11);
    AlarmSync.applySnapshot(state, SyncFixtures.snap([op["oid"]]), 3);
    Test.assertEqual(AlarmSync.view(state)[0]["h"], 7);
    Test.assert(AlarmSync.view(state)[0]["p"] == null);
    return true;
}

(:test)
function testStateSurvivesStorage(logger as Test.Logger) as Boolean {
    var state = AlarmSync.newState();
    AlarmSync.applySnapshot(state, SyncFixtures.snap([]), 42);
    AlarmSync.addOp(state, "del", "a1", null, 43);
    AlarmSync.save(state);
    var loaded = AlarmSync.load();
    Test.assertEqual((loaded["alarms"] as Array).size(), 2);
    Test.assertEqual((loaded["outbox"] as Array).size(), 1);
    Test.assertEqual(loaded["syncedAt"], 42);
    Test.assertEqual(loaded["seq"], state["seq"]);
    Test.assertEqual(loaded["dev"], state["dev"]);
    AlarmSync.save(AlarmSync.newState());
    return true;
}

(:test)
function testValueCoercion(logger as Test.Logger) as Boolean {
    Test.assertEqual(AlarmSync.num(5), 5);
    Test.assertEqual(AlarmSync.num(5l), 5);
    Test.assertEqual(AlarmSync.num(5.0d), 5);
    Test.assert(AlarmSync.num("5") == null);
    Test.assert(AlarmSync.num(null) == null);
    Test.assertEqual(AlarmSync.bool(true), true);
    Test.assertEqual(AlarmSync.bool(0), false);
    Test.assert(AlarmSync.bool("yes") == null);
    return true;
}
