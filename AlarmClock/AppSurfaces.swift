import Foundation

/// Installs the real widget/Live Activity implementations on the app's store.
/// Tests and previews keep the store's no-op defaults.
enum AppSurfaces {
    static func install(on store: AlarmStore) {
        store.widgetSnapshots = WidgetSnapshotPublisher()
    }
}
