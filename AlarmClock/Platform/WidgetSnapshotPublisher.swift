import Foundation
import WidgetKit

/// Writes the snapshot into the App Group container and asks WidgetKit to
/// reload. The file is rewritten on every publish (cheap, keeps the horizon
/// fresh) but timelines are only reloaded when the upcoming fires actually
/// changed, to stay well inside WidgetKit's reload budget. If the App Group
/// container is unavailable nothing is written and the widget shows its
/// "Open Alarm to set up" state.
final class WidgetSnapshotPublisher: WidgetSnapshotPublishing {

    private var lastReloaded: [WidgetSnapshot.Occurrence]?

    func publish(_ snapshot: WidgetSnapshot) {
        guard SharedSnapshotStore.write(snapshot) else { return }
        guard snapshot.occurrences != lastReloaded else { return }
        lastReloaded = snapshot.occurrences
        WidgetCenter.shared.reloadAllTimelines()
    }
}
