import Toybox.Lang;
import Toybox.Time;
import Toybox.Timer;

// Simulator builds only (sim.jungle): plays the iPhone app so the whole
// edit -> sync -> snapshot loop runs in the simulator. It applies ops the
// way the phone does (minus scheduling) and answers every sync with a
// snapshot that acks them, after a short delay like a real round trip.
(:noradio)
module FakePhone {

    const DELAY_MS = 400;

    var alarms as Array or Null = null;
    var timer as Timer.Timer or Null = null;
    var reply as Dictionary or Null = null;

    function seed() as Array {
        var now = Time.now().value();
        return [
            {"id" => "demo-1", "h" => 6, "m" => 30, "d" => [1, 2, 3, 4, 5], "l" => "Work", "e" => true,
             "sn" => true, "sm" => 9, "u" => 0, "nf" => now + 12 * 3600},
            {"id" => "demo-2", "h" => 8, "m" => 0, "d" => [6, 7], "l" => "Alarm", "e" => true,
             "sn" => true, "sm" => 10, "u" => 0, "nf" => now + 30 * 3600, "ov" => {"7" => [9, 0]}},
            {"id" => "demo-3", "h" => 14, "m" => 0, "d" => [], "l" => "Nap", "e" => false,
             "sn" => false, "sm" => 9, "u" => 0}
        ];
    }

    function receive(msg as Dictionary) as Void {
        if (alarms == null) {
            alarms = seed();
        }
        var ops = msg["ops"] as Array;
        var acked = [];
        for (var i = 0; i < ops.size(); i++) {
            var list = AlarmSync.replay(alarms, ops[i]);
            for (var j = 0; j < list.size(); j++) {
                list[j].remove("p");
                if (list[j]["sk"] == AlarmSync.SKIP_PENDING) {
                    list[j]["sk"] = list[j]["nf"] != null ? list[j]["nf"] : Time.now().value();
                }
            }
            alarms = list;
            acked.add(ops[i]["oid"]);
        }
        reply = {"t" => "snap", "v" => 1, "ts" => Time.now().value(), "ack" => acked, "alarms" => alarms};
        timer = new Timer.Timer();
        timer.start(new Lang.Method(FakePhone, :deliver), DELAY_MS, false);
    }

    function deliver() as Void {
        Controller.onSnapshot(reply);
    }
}
