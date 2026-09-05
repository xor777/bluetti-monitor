import AppKit
import BluettiCore
import Combine
import Foundation

enum NotificationActionResult: Equatable, Sendable {
    case success(UserFacingConfirmation)
    case failure(UserFacingError)
    case unavailable(NotificationHealth)
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
    @Published private(set) var lastError: UserFacingError?
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
    @Published private(set) var loginItemError: UserFacingError?
    @Published private(set) var notificationActionResult: NotificationActionResult?
    @Published private(set) var isFirstRunComplete: Bool
    @Published private(set) var hasStartedFirstConnection = false
    @Published private(set) var isDeviceRescanInProgress = false
    @Published private(set) var languagePreference: LanguagePreference
    @Published private(set) var appearancePreference: AppearancePreference

    private let notifications: any NotificationServicing
    private let loginItems: any LoginItemManaging
    private let preferences: AppPreferencesStore
    private let preferredLanguages: () -> [String]
    var reconnectAction: (() -> Void)?
    var openBluetoothPrivacySettingsAction: (() -> Void)?
    var openBluetoothControlSettingsAction: (() -> Void)?
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
    private let deviceRescanProgressDuration: TimeInterval
    private var deviceRescanGeneration: UInt64 = 0
    private var awaitingDeviceRescanReset = false
    private var deviceRescanBaselineIDs: Set<UUID> = []

    init(
        notifications: any NotificationServicing,
        loginItems: any LoginItemManaging,
        isFirstRunComplete: Bool,
        preferences: AppPreferencesStore = AppPreferencesStore(),
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages },
        deviceRescanProgressDuration: TimeInterval = 3
    ) {
        self.notifications = notifications
        self.loginItems = loginItems
        self.isFirstRunComplete = isFirstRunComplete
        self.preferences = preferences
        self.preferredLanguages = preferredLanguages
        languagePreference = preferences.language
        appearancePreference = preferences.appearance
        self.deviceRescanProgressDuration = deviceRescanProgressDuration
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
            self?.notificationActionResult = .failure(.notificationSchedulingFailed(detail))
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
        ), localizer: localizer)
    }

    var notificationReadiness: NotificationReadinessPresentation {
        NotificationReadinessPresentation.make(notificationHealth, localizer: localizer)
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

    var localizer: AppLocalizer {
        AppLocalizer(
            language: languagePreference,
            preferredLanguages: preferredLanguages()
        )
    }

    var availableLanguageOptions: [LanguageOption] {
        AppLocalizer.availableLanguageOptions
    }

    func setLanguage(_ language: LanguagePreference) {
        preferences.language = language
        languagePreference = language
    }

    func setAppearance(_ appearance: AppearancePreference) {
        preferences.appearance = appearance
        appearancePreference = appearance
    }

    func refreshSystemLanguage() {
        guard languagePreference == .system else { return }
        objectWillChange.send()
    }

    var deviceName: String {
        guard let model = snapshot.model else { return "Premium 100 V2" }
        return model.uppercased() == "PR100V2" ? "Premium 100 V2" : model
    }

    func setBluetooth(_ value: BluetoothAvailability) {
        bluetooth = value
        if value != .poweredOn {
            finishDeviceRescanProgress()
        }
    }

    func setStationSelection(_ value: StationSelectionSnapshot) {
        stationSelection = value
        updateDeviceRescanProgress(for: value)
        completeFirstRunIfReady()
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
        completeFirstRunIfReady()
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
        completeFirstRunIfReady()
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
            notifications.deliver(event, localizer: localizer)
        }
        completeFirstRunIfReady()
    }

    func monitoringLost(error: UserFacingError?) {
        connection = .disconnected
        freshness = .lost
        powerConfirmedInCurrentSession = false
        batteryObservedInCurrentSession = false
        lastBatteryUpdate = nil
        if let error { lastError = error }
        if let event = notificationPolicy.monitoringLost() {
            notifications.deliver(event, localizer: localizer)
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
        completeFirstRunIfReady()
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
            notifications.deliver(event, localizer: localizer)
        }
        deliverLowBatteryAlertIfNeeded(at: date)
        completeFirstRunIfReady()
    }

    func noteError(_ message: UserFacingError) {
        lastError = message
    }

    func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
    }

    func startMonitoring() {
        hasStartedFirstConnection = true
        startMonitoringAction?()
    }

    func beginDeviceSelection() {
        finishDeviceRescanProgress()
        beginDeviceSelectionAction?()
    }

    func cancelDeviceSelection() {
        finishDeviceRescanProgress()
        cancelDeviceSelectionAction?()
    }

    func rescanDevices() {
        beginDeviceRescanProgress()
        rescanDeviceSelectionAction?()
    }

    func selectDevice(_ id: UUID) {
        finishDeviceRescanProgress()
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
                    notificationActionResult = .unavailable(health)
                    return
                }
                try await notifications.schedule(.test, localizer: localizer)
                notificationActionResult = .success(.notificationScheduled)
            } catch {
                notificationActionResult = .failure(
                    .notificationSchedulingFailed(error.localizedDescription)
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
                    notificationActionResult = .success(.notificationsAllowed)
                } else {
                    notificationActionResult = .unavailable(health)
                }
            } catch {
                notificationActionResult = .failure(
                    .notificationPermissionFailed(error.localizedDescription)
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
        loginItemError = nil
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            loginItemStatus = try loginItems.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemStatus = loginItems.currentStatus()
            loginItemError = loginItemStatus == .unavailable
                ? nil
                : .system(error.localizedDescription)
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

    private func completeFirstRunIfReady() {
        guard FirstRunReadiness.isSatisfied(
            selectedID: selectedPeripheralID,
            connection: connection,
            power: power,
            freshness: freshness,
            powerConfirmedInCurrentSession: powerConfirmedInCurrentSession
        ) else {
            return
        }
        completeFirstRun()
    }

    func resetForDeviceChange() {
        finishDeviceRescanProgress()
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

    private func beginDeviceRescanProgress() {
        deviceRescanGeneration &+= 1
        let generation = deviceRescanGeneration
        awaitingDeviceRescanReset = true
        deviceRescanBaselineIDs = Set(stationSelection.candidates.map(\.id))
        isDeviceRescanInProgress = true

        DispatchQueue.main.asyncAfter(deadline: .now() + deviceRescanProgressDuration) { [weak self] in
            guard let self, generation == self.deviceRescanGeneration else { return }
            self.finishDeviceRescanProgress()
        }
    }

    private func updateDeviceRescanProgress(for selection: StationSelectionSnapshot) {
        guard isDeviceRescanInProgress else { return }
        let candidateIDs = Set(selection.candidates.map(\.id))

        if awaitingDeviceRescanReset {
            awaitingDeviceRescanReset = false
            deviceRescanBaselineIDs = candidateIDs
            return
        }

        if selection.mode != .choosing || !candidateIDs.isSubset(of: deviceRescanBaselineIDs) {
            finishDeviceRescanProgress()
        }
    }

    private func finishDeviceRescanProgress() {
        guard isDeviceRescanInProgress || awaitingDeviceRescanReset else { return }
        deviceRescanGeneration &+= 1
        awaitingDeviceRescanReset = false
        deviceRescanBaselineIDs.removeAll(keepingCapacity: true)
        isDeviceRescanInProgress = false
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
            "Ошибка: \(lastError?.diagnosticDetail ?? "—")",
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
            notifications.deliver(event, localizer: localizer)
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
