import Foundation
import ConnectIQ

/// The Connect IQ Mobile SDK side of `WatchTransport`.
///
/// The SDK talks to the watch over Bluetooth on its own; Garmin Connect is
/// only needed once, to pick which watches this app may use (it hands the
/// list back through the `alarmclock-ciq` URL scheme). The chosen devices are
/// cached so later launches, including Bluetooth background relaunches,
/// reconnect without Garmin Connect.
final class GarminConnection: NSObject, ObservableObject, WatchTransport {
    static let shared = GarminConnection()

    /// Must match the `id` in garmin/manifest.xml.
    static let watchAppId = UUID(uuidString: "0d09aa3d-ace2-4cae-94fc-19b901ed1374")!
    static let urlScheme = "alarmclock-ciq"
    private static let restorationId = "com.devansh.alarmclock.connectiq"
    private static let devicesKey = "garmin.devices"

    struct Watch: Identifiable, Equatable {
        let id: UUID
        let name: String
        var status: Status
        /// The watch app's install state, once asked.
        var appInstalled: Bool?

        enum Status: Equatable {
            case notConnected, connecting, ready, bluetoothOff, unavailable
        }
    }

    @Published private(set) var watches: [Watch] = []
    /// Garmin Connect isn't installed; device selection can't run.
    @Published private(set) var needsGarminConnect = false
    @Published private(set) var lastSendError: String?

    var onMessage: ((Any) -> Void)?
    var onWatchReady: (() -> Void)?

    private var started = false
    private var devices: [IQDevice] = []
    private var apps: [UUID: IQApp] = [:]
    /// Devices whose Bluetooth characteristics are discovered. Since SDK 1.8
    /// "connected" alone is not enough to send.
    private var readyDevices: Set<UUID> = []
    private var connectIQ: ConnectIQ? { ConnectIQ.sharedInstance() }

    /// Starts the SDK if a watch was chosen before. Nothing happens (and no
    /// Bluetooth permission prompt appears) until the user connects a watch.
    func startIfPaired() {
        let cached = Self.loadDevices()
        guard !cached.isEmpty else { return }
        start()
        use(cached)
    }

    /// Opens Garmin Connect to choose watches; the answer comes back via `handle(url:)`.
    func chooseWatches() {
        start()
        connectIQ?.showDeviceSelection()
    }

    /// Handles Garmin Connect's device-selection callback.
    /// - Returns: false when the URL isn't for this connection.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme == Self.urlScheme else { return false }
        start()
        let chosen = connectIQ?.parseDeviceSelectionResponse(from: url) as? [IQDevice] ?? []
        Self.saveDevices(chosen)
        use(chosen)
        return true
    }

    /// Forgets the chosen watches.
    func disconnectAll() {
        connectIQ?.unregister(forAllDeviceEvents: self)
        connectIQ?.unregister(forAllAppMessages: self)
        Self.saveDevices([])
        devices = []
        apps = [:]
        readyDevices = []
        watches = []
    }

    func send(_ message: [String: Any]) {
        for device in devices where readyDevices.contains(device.uuid) {
            guard let app = apps[device.uuid] else { continue }
            connectIQ?.sendMessage(message, to: app, progress: { _, _ in }) { [weak self] result in
                DispatchQueue.main.async {
                    self?.lastSendError = result == .success ? nil : NSStringFromSendMessageResult(result)
                }
            }
        }
    }

    // MARK: - Private

    private func start() {
        guard !started else { return }
        started = true
        connectIQ?.initialize(withUrlScheme: Self.urlScheme, uiOverrideDelegate: self,
                              stateRestorationIdentifier: Self.restorationId)
    }

    private func use(_ chosen: [IQDevice]) {
        connectIQ?.unregister(forAllDeviceEvents: self)
        connectIQ?.unregister(forAllAppMessages: self)
        devices = chosen
        apps = [:]
        readyDevices = readyDevices.intersection(chosen.compactMap { $0.uuid })
        watches = chosen.map { Watch(id: $0.uuid, name: $0.friendlyName ?? $0.modelName ?? "Garmin watch",
                                     status: .connecting) }
        for device in chosen {
            connectIQ?.register(forDeviceEvents: device, delegate: self)
            if let app = IQApp(uuid: Self.watchAppId, store: Self.watchAppId, device: device) {
                apps[device.uuid] = app
                connectIQ?.register(forAppMessages: app, delegate: self)
            }
            if let status = connectIQ?.getDeviceStatus(device) {
                update(device.uuid) { $0.status = Self.status(status, ready: false) }
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout Watch) -> Void) {
        guard let index = watches.firstIndex(where: { $0.id == id }) else { return }
        change(&watches[index])
    }

    private static func status(_ status: IQDeviceStatus, ready: Bool) -> Watch.Status {
        switch status {
        case .connected: return ready ? .ready : .connecting
        case .notConnected: return .notConnected
        case .bluetoothNotReady: return .bluetoothOff
        default: return .unavailable
        }
    }

    private func checkAppInstalled(on device: IQDevice) {
        guard let app = apps[device.uuid] else { return }
        connectIQ?.getAppStatus(app) { [weak self] status in
            DispatchQueue.main.async {
                self?.update(device.uuid) { $0.appInstalled = status?.isInstalled }
            }
        }
    }

    private static func loadDevices() -> [IQDevice] {
        guard let data = UserDefaults.standard.data(forKey: devicesKey) else { return [] }
        return (try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: IQDevice.self, from: data)) ?? []
    }

    private static func saveDevices(_ devices: [IQDevice]) {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: devices, requiringSecureCoding: true)
        UserDefaults.standard.set(data, forKey: devicesKey)
    }
}

extension GarminConnection: IQUIOverrideDelegate, IQDeviceEventDelegate, IQAppMessageDelegate {
    func needsToInstallConnectMobile() {
        DispatchQueue.main.async { self.needsGarminConnect = true }
    }

    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        DispatchQueue.main.async {
            if status != .connected { self.readyDevices.remove(device.uuid) }
            let ready = self.readyDevices.contains(device.uuid)
            self.update(device.uuid) { $0.status = Self.status(status, ready: ready) }
        }
    }

    func deviceCharacteristicsDiscovered(_ device: IQDevice) {
        DispatchQueue.main.async {
            self.readyDevices.insert(device.uuid)
            self.update(device.uuid) { $0.status = .ready }
            self.checkAppInstalled(on: device)
            self.onWatchReady?()
        }
    }

    func receivedMessage(_ message: Any, from app: IQApp) {
        DispatchQueue.main.async {
            self.onMessage?(message)
        }
    }
}
