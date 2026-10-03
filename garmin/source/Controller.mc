import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Foreground glue: owns the sync state while the app is open, sends the
// outbox to the phone, takes in snapshots and keeps the open menus current.
module Controller {

    // Don't resend the outbox on every snapshot; once per this many seconds.
    const RESEND_AFTER = 10;
    const RETRY_EVERY = 60;

    var state as Dictionary = {};
    var lastSendAt as Number = 0;
    var lastSendFailed as Boolean = false;
    var listMenu as AlarmListMenu or Null = null;
    var detailMenu as AlarmDetailMenu or Null = null;
    var retryTimer as Timer.Timer or Null = null;

    function start() as [WatchUi.Views, WatchUi.InputDelegates] {
        state = AlarmSync.load();
        Communications.registerForPhoneAppMessages(new Lang.Method(Controller, :onPhoneMessage));
        if (Background has :registerForPhoneAppMessageEvent) {
            Background.registerForPhoneAppMessageEvent();
        }
        listMenu = new AlarmListMenu();
        send();
        // Retry unsent edits while the app is open (phone out of range,
        // iPhone app not running yet), and keep "Synced 2 min ago" current.
        retryTimer = new Timer.Timer();
        retryTimer.start(new Lang.Method(Controller, :onTick), RETRY_EVERY * 1000, true);
        return [listMenu, new AlarmListDelegate()];
    }

    function onTick() as Void {
        if (pendingCount() > 0 && now() - lastSendAt >= RETRY_EVERY) {
            send();
        }
        refresh();
    }

    function now() as Number {
        return Time.now().value();
    }

    function is24() as Boolean {
        return System.getDeviceSettings().is24Hour;
    }

    function phoneConnected() as Boolean {
        return System.getDeviceSettings().phoneConnected;
    }

    function alarms() as Array {
        return AlarmSync.view(state);
    }

    function alarm(id as String) as Dictionary or Null {
        return AlarmSync.find(alarms(), id);
    }

    function pendingCount() as Number {
        return (state["outbox"] as Array).size();
    }

    // Records an edit, shows it at once and sends it to the phone.
    function edit(kind as String, id as String, extra as Dictionary or Null) as Void {
        AlarmSync.addOp(state, kind, id, extra, now());
        AlarmSync.save(state);
        refresh();
        send();
    }

    // A new one-shot alarm at h:m. Returns its id.
    function create(h as Number, m as Number) as String {
        var id = AlarmSync.newAlarmId(state);
        edit("put", id, {"f" => {"h" => h, "m" => m, "d" => []}});
        return id;
    }

    function send() as Void {
        lastSendAt = now();
        transmit(AlarmSync.syncMessage(state));
    }

    (:radio)
    function transmit(msg as Dictionary) as Void {
        Communications.transmit(msg, null, new SyncListener());
    }

    // Simulator builds (sim.jungle): the simulator can't reach an iPhone, so a
    // fake phone answers instead.
    (:noradio)
    function transmit(msg as Dictionary) as Void {
        FakePhone.receive(msg);
    }

    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        onSnapshot(msg.data);
    }

    function onSnapshot(data) as Void {
        if (!AlarmSync.applySnapshot(state, data, now())) {
            return;
        }
        AlarmSync.save(state);
        lastSendFailed = false;
        // A snapshot the phone pushed on its own (watch reconnected, edit on
        // the phone) doesn't ack edits made while it was out of reach.
        if (pendingCount() > 0 && now() - lastSendAt >= RESEND_AFTER) {
            send();
        }
        refresh();
    }

    function onSendResult(ok as Boolean) as Void {
        lastSendFailed = !ok;
        refresh();
    }

    // The background service changed storage.
    function reload() as Void {
        var stored = AlarmSync.load();
        // Keep edits made in this session that the stored copy predates.
        if ((stored["seq"] as Number) < (state["seq"] as Number)) {
            stored["outbox"] = state["outbox"];
            stored["seq"] = state["seq"];
            stored["dev"] = state["dev"];
        }
        state = stored;
        refresh();
    }

    function refresh() as Void {
        if (listMenu != null) {
            listMenu.rebuild();
        }
        if (detailMenu != null) {
            detailMenu.rebuild();
        }
        WatchUi.requestUpdate();
    }
}

(:radio)
class SyncListener extends Communications.ConnectionListener {

    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() as Void {
        Controller.onSendResult(true);
    }

    function onError() as Void {
        Controller.onSendResult(false);
    }
}
