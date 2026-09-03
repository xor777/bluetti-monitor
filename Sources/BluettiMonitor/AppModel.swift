import AppKit
import BluettiCore
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var bluetooth: BluetoothAvailability = .unknown
    @Published private(set) var connection: DeviceConnectionState = .disconnected
    @Published private(set) var power: ExternalPowerState = .unknown
    @Published private(set) var freshness: DataFreshness = .lost
    @Published private(set) var snapshot = DeviceSnapshot()
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var lastTransition: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var notificationHealth: NotificationHealth = .unknown
    @Published private(set) var scanningFor: TimeInterval = 0
    @Published private(set) var isPopoverVisible = false

    let notifications: NotificationService
    var reconnectAction: (() -> Void)?
    var openBluetoothSettingsAction: (() -> Void)?
    var peripheralID: UUID?

    private var notificationPolicy = NotificationPolicy()
    private var scanGeneration: UInt64 = 0
    private var everReady = false

    init(notifications: NotificationService) {
        self.notifications = notifications
        notifications.healthChanged = { [weak self] health in
            self?.notificationHealth = health
        }
    }

    var presentation: StatusPresentation {
        StatusPresentation.make(.init(
            bluetooth: bluetooth,
            connection: connection,
            power: power,
            freshness: freshness,
            scanningFor: scanningFor,
            inputPower: snapshot.acInputPower,
            outputPower: snapshot.acOutputPower
        ))
    }

    var deviceName: String {
        guard let model = snapshot.model else { return "Premium 100 V2" }
        return model.uppercased() == "PR100V2" ? "Premium 100 V2" : model
    }

    func setBluetooth(_ value: BluetoothAvailability) {
        bluetooth = value
    }

    func setCentralConnection(
        _ state: DeviceConnectionState,
        peripheralID: UUID?
    ) {
        if let peripheralID { self.peripheralID = peripheralID }
        if everReady && (state == .scanning || state == .connecting) {
            connection = .disconnected
        } else if state == .connected {
            connection = .connecting
        } else {
            connection = state
        }

        scanGeneration &+= 1
        let generation = scanGeneration
        if state == .scanning && !everReady {
            scanningFor = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self, generation == self.scanGeneration, self.connection == .scanning else { return }
                self.scanningFor = 10
            }
        } else {
            scanningFor = 0
        }
    }

    func apply(_ patch: TelemetryPatch, at date: Date = Date()) {
        snapshot.apply(patch)
        lastUpdate = date
    }

    func setFreshness(_ value: DataFreshness) {
        freshness = value
    }

    func monitoringReady() {
        everReady = true
        connection = .connected
        freshness = .fresh
        lastError = nil
        if let event = notificationPolicy.monitoringReady() {
            notifications.deliver(event)
        }
    }

    func monitoringLost(error: String?) {
        connection = .disconnected
        freshness = .lost
        if let error, !error.isEmpty { lastError = error }
        if let event = notificationPolicy.monitoringLost() {
            notifications.deliver(event)
        }
    }

    func handle(_ transition: PowerTransition) {
        switch transition {
        case let .initial(state): power = state
        case let .changed(_, state):
            power = state
            lastTransition = Date()
        }
        if let event = notificationPolicy.handle(transition) {
            notifications.deliver(event)
        }
    }

    func noteError(_ message: String) {
        lastError = message
    }

    func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
    }

    func testNotification() {
        notifications.deliver(.test)
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
    }

    var diagnostics: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let maskedID: String
        if let raw = peripheralID?.uuidString {
            maskedID = "\(raw.prefix(4))…\(raw.suffix(4))"
        } else {
            maskedID = "—"
        }
        let updated = lastUpdate.map { ISO8601DateFormatter().string(from: $0) } ?? "—"
        return [
            "Bluetti Monitor \(version)",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Модель: \(deviceName)",
            "Устройство: \(maskedID)",
            "Bluetooth: \(bluetooth)",
            "Связь: \(connection)",
            "Питание: \(power)",
            "Обновлено: \(updated)",
            "Ошибка: \(lastError ?? "—")",
        ].joined(separator: "\n")
    }
}
