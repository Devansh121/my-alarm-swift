import Foundation
import AppIntents
import ActivityKit

/// Where the app plugs in its "stop this alarm" path. Set at app launch to the
/// same store call the notification's Stop action uses. Stays nil in the
/// widget extension process.
enum SnoozeStopRouter {
    static var handler: ((String) -> Void)?
}

/// The Live Activity's Stop button. As a `LiveActivityIntent` the system runs
/// `perform()` in the app's process (launching it in the background if
/// needed), so the stop goes through the store exactly like the
/// notification's Stop action: the pending snooze is cancelled and a one-shot
/// alarm is disabled. The activity is then ended here directly as well, so it
/// disappears even if the router were somehow unset.
struct StopSnoozeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Alarm"
    static var description = IntentDescription("Stops a snoozed alarm so it does not ring again.")

    @Parameter(title: "Alarm ID")
    var alarmId: String

    init() {}

    init(alarmId: String) {
        self.alarmId = alarmId
    }

    func perform() async throws -> some IntentResult {
        let id = alarmId
        await MainActor.run {
            SnoozeStopRouter.handler?(id)
        }
        for activity in Activity<SnoozeActivityAttributes>.activities
        where activity.attributes.alarmId == id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}
