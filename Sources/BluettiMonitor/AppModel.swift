import AppKit
import BluettiCore
import Combine
import Foundation

enum NotificationActionResult: Equatable, Sendable {
    case success(String)
    case failure(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var bluetooth: BluetoothAvailability = .unknown
    @Published private(set) var connection: DeviceConnectionState = .disconnected
    @Published private(set) var power: ExternalPowerState = .unknown
    @Published private(set) var freshness: DataFreshness = .lost
    @Published private(set) var snapshot = DeviceSnapshot()
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var lastTransition: Date?
    @Published private(set) var outageStartedAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var notificationHealth: NotificationHealth = .unknown
    @Published private(set) var scanningFor: TimeInterval = 0
    @Published private(set) var isPopoverVisible = false
    @Published private(set) var powerConfirmedInCurrentSession = false
    @Published private(set) var stationSelection = StationSelectionSnapshot(
        selectedID: nil,
        candidates: [],
        mode: .initialDiscovery
    )
    @Published private(set) var loginItemStatus: LoginItemStatus = .unknown
    @Published private(set) var loginItemError: String?
    @Published private(set) var notificationActionResult: NotificationActionResult?
    @Published private(set) var isFirstRunComplete: Bool

    private let notifications: any NotificationServicing
    private let loginItems: any LoginItemManaging
    var reconnectAction: (() -> Void)?
    var openBluetoothSettingsAction: (() -> Void)?
    var beginDeviceSelectionAction: (() -> Void)?
    var cancelDeviceSelectionAction: (() -> Void)?
    var rescanDeviceSelectionAction: (() -> Void)?
    var selectDeviceAction: ((UUID) -> Void)?
    var completeFirstRunAction: (() -> Void)?
    var startMonitoringAction: (() -> Void)?
    var peripheralID: UUID?

    private var notificationPolicy = NotificationPolicy()
    private var lowBatteryAlertPolicy = LowBatteryAlertPolicy()
    private var outageTracker = OutageTracker()
    private let batteryTiming = BatterySampleTiming()
    private var scanGeneration: UInt64 = 0
    private var everReady = false
    private var batteryObservedInCurrentSession = false
    private var lastBatteryUpdate: Date?

    init(
        notifications: any NotificationServicing,
        loginItems: any LoginItemManaging,
        isFirstRunComplete: Bool
    ) {
        self.notifications = notifications
        self.loginItems = loginItems
        self.isFirstRunComplete = isFirstRunComplete
        notifications.healthChanged = { [weak self] health in
            guard let self else { return }
            let previousHealth = notificationHealth
            notificationHealth = health
            if health == .available,
               previousHealth != .available,
               case .failure? = notificationActionResult
            {
                notificationActionResult = nil
            }
        }
        notifications.schedulingFailed = { [weak self] detail in
            self?.notificationActionResult = .failure(
                "Не удалось запланировать уведомление: \(detail)"
            )
        }
    }

    var presentation: StatusPresentation {
        StatusPresentation.make(.init(
            bluetooth: bluetooth,
            connection: connection,
            power: power,
            freshness: freshness,
            powerConfirmedInCurrentSession: powerConfirmedInCurrentSession,
            scanningFor: scanningFor,
            inputPower: snapshot.acInputPower,
            outputPower: snapshot.acOutputPower
        ))
    }

    var notificationReadiness: NotificationReadinessPresentation {
        NotificationReadinessPresentation.make(notificationHealth)
    }

    var lowBatteryVisualState: LowBatteryVisualState {
        LowBatteryAlertPolicy.visualState(lowBatteryInput(at: Date()))
    }

    var stationCandidates: [StationCandidate] { stationSelection.candidates }
    var selectedPeripheralID: UUID? { stationSelection.selectedID }
    var isSelectingDevice: Bool { stationSelection.isChoosing }
    var canCancelDeviceSelection: Bool {
        stationSelection.isChoosing && stationSelection.selectedID != nil
    }
    var launchAtLoginToggleValue: Bool {
        loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }

    var deviceName: String {
        guard let model = snapshot.model else { return "Premium 100 V2" }
        return model.uppercased() == "PR100V2" ? "Premium 100 V2" : model
    }

    func setBluetooth(_ value: BluetoothAvailability) {
        bluetooth = value
    }

    func setStationSelection(_ value: StationSelectionSnapshot) {
        stationSelection = value
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
        if patch.batteryPercent != nil {
            batteryObservedInCurrentSession = true
            lastBatteryUpdate = date
            deliverLowBatteryAlertIfNeeded(at: date)
        }
    }

    func setFreshness(_ value: DataFreshness) {
        freshness = value
    }

    func beginMonitoringSession() {
        snapshot.clearTelemetryForNewSession()
        power = .unknown
        powerConfirmedInCurrentSession = false
        batteryObservedInCurrentSession = false
        lastBatteryUpdate = nil
        freshness = .lost
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
        powerConfirmedInCurrentSession = false
        batteryObservedInCurrentSession = false
        lastBatteryUpdate = nil
        if let error, !error.isEmpty { lastError = error }
        if let event = notificationPolicy.monitoringLost() {
            notifications.deliver(event)
        }
    }

    func confirmPowerState(_ state: ExternalPowerState, at date: Date = Date()) {
        power = state
        powerConfirmedInCurrentSession = true
        if state == .online {
            outageTracker.handle(.changed(from: .offline, to: .online), at: date.timeIntervalSinceReferenceDate)
            outageStartedAt = outageTracker.startedAt.map(Date.init(timeIntervalSinceReferenceDate:))
        }
        deliverLowBatteryAlertIfNeeded(at: date)
    }

    func handle(_ transition: PowerTransition, at date: Date = Date()) {
        switch transition {
        case let .initial(state):
            power = state
        case let .changed(_, state):
            power = state
            lastTransition = date
        }
        powerConfirmedInCurrentSession = true
        outageTracker.handle(transition, at: date.timeIntervalSinceReferenceDate)
        outageStartedAt = outageTracker.startedAt.map(Date.init(timeIntervalSinceReferenceDate:))
        if let event = notificationPolicy.handle(
            transition,
            batteryPercent: currentValidBatteryPercentForNotification(at: date)
        ) {
            notifications.deliver(event)
        }
        deliverLowBatteryAlertIfNeeded(at: date)
    }

    func noteError(_ message: String) {
        lastError = message
    }

    func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
    }

    func startMonitoring() {
        startMonitoringAction?()
    }

    func beginDeviceSelection() {
        beginDeviceSelectionAction?()
    }

    func cancelDeviceSelection() {
        cancelDeviceSelectionAction?()
    }

    func rescanDevices() {
        rescanDeviceSelectionAction?()
    }

    func selectDevice(_ id: UUID) {
        selectDeviceAction?(id)
    }

    func testNotification() {
        notificationActionResult = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                var health = notificationHealth
                if health == .unknown {
                    await notifications.refreshHealth()
                    health = notificationHealth
                }
                if health == .notDetermined {
                    health = try await notifications.requestAuthorization()
                }
                guard health == .available else {
                    notificationActionResult = .failure(
                        NotificationReadinessPresentation.make(health).detail
                    )
                    return
                }
                try await notifications.schedule(.test)
                notificationActionResult = .success(
                    "Тестовое уведомление запланировано в macOS"
                )
            } catch {
                notificationActionResult = .failure(
                    "Не удалось запланировать уведомление: \(error.localizedDescription)"
                )
            }
        }
    }

    func requestNotificationAuthorization() {
        notificationActionResult = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let health = try await notifications.requestAuthorization()
                if health == .available {
                    notificationActionResult = .success("Уведомления разрешены")
                } else {
                    notificationActionResult = .failure(
                        NotificationReadinessPresentation.make(health).detail
                    )
                }
            } catch {
                notificationActionResult = .failure(
                    "Не удалось запросить разрешение: \(error.localizedDescription)"
                )
            }
        }
    }

    func refreshNotificationHealth() async {
        await notifications.refreshHealth()
    }

    func openNotificationSettings() {
        notifications.openSettings()
    }

    func clearNotificationActionResult() {
        notificationActionResult = nil
    }

    func refreshLoginItemStatus() {
        loginItemStatus = loginItems.currentStatus()
        if loginItemStatus == .unavailable {
            loginItemError = "Автозапуск недоступен для этой копии приложения"
        } else {
            loginItemError = nil
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            loginItemStatus = try loginItems.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemStatus = loginItems.currentStatus()
            loginItemError = error.localizedDescription
        }
    }

    func openLoginItemSettings() {
        loginItems.openSystemSettings()
    }

    func refreshSystemHealth() async {
        await notifications.refreshHealth()
        refreshLoginItemStatus()
    }

    func completeFirstRun() {
        guard !isFirstRunComplete else { return }
        completeFirstRunAction?()
        isFirstRunComplete = true
    }

    func resetForDeviceChange() {
        snapshot = DeviceSnapshot()
        power = .unknown
        freshness = .lost
        lastUpdate = nil
        lastTransition = nil
        outageStartedAt = nil
        lastError = nil
        peripheralID = nil
        scanningFor = 0
        connection = .disconnected
        powerConfirmedInCurrentSession = false
        batteryObservedInCurrentSession = false
        lastBatteryUpdate = nil
        everReady = false
        notificationPolicy.resetForDeviceChange()
        lowBatteryAlertPolicy.resetForDeviceChange()
        outageTracker.reset()
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

    private func lowBatteryInput(at date: Date) -> LowBatteryAlertInput {
        LowBatteryAlertInput(
            power: power,
            powerConfirmedInCurrentSession: powerConfirmedInCurrentSession,
            batteryPercent: snapshot.batteryPercent,
            batteryFreshness: effectiveBatteryFreshness(at: date),
            batteryObservedInCurrentSession: batteryObservedInCurrentSession
        )
    }

    private func currentValidBatteryPercentForNotification(at date: Date) -> Int? {
        lowBatteryInput(at: date).validFreshBatteryPercent
    }

    private func deliverLowBatteryAlertIfNeeded(at date: Date) {
        if let event = lowBatteryAlertPolicy.evaluate(lowBatteryInput(at: date)) {
            notifications.deliver(event)
        }
    }

    private func effectiveBatteryFreshness(at date: Date) -> DataFreshness {
        guard freshness == .fresh else { return freshness }
        return batteryTiming.freshness(
            sampledAt: lastBatteryUpdate?.timeIntervalSinceReferenceDate,
            now: date.timeIntervalSinceReferenceDate,
            observedInCurrentSession: batteryObservedInCurrentSession
        )
    }
}
