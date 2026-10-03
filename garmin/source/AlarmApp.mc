import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Entry point. Marked background so the service delegate can be created
// when a phone message arrives while the app is closed.
(:background)
class AlarmApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new SyncServiceDelegate()];
    }

    (:typecheck(false))
    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return Controller.start();
    }

    // The background service wrote a snapshot while the app was open.
    (:typecheck(false))
    function onStorageChanged() as Void {
        Controller.reload();
    }
}

// Stores snapshots that arrive while the app is closed, so the list is
// current the next time it opens.
(:background)
class SyncServiceDelegate extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onPhoneAppMessage(msg as Communications.PhoneAppMessage) as Void {
        var state = AlarmSync.load();
        if (AlarmSync.applySnapshot(state, msg.data, Time.now().value())) {
            AlarmSync.save(state);
        }
        Background.exit(null);
    }
}
