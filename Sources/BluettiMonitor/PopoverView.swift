import AppKit
import BluettiCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @State private var route: PopoverScreen = .normal

    var body: some View {
        let localizer = model.localizer
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            PopoverContentView(
                state: makeState(now: timeline.date),
                actions: actions
            )
        }
        .environment(\.appLocalizer, localizer)
        .environment(\.locale, localizer.locale)
        .preferredColorScheme(model.appearancePreference.colorScheme)
        .onChange(of: model.isPopoverVisible) { visible in
            guard !visible else { return }
            if model.canCancelDeviceSelection {
                model.cancelDeviceSelection()
            }
            route = .normal
        }
    }

    private func makeState(now: Date) -> PopoverViewState {
        let selectedCandidate = model.stationCandidates.first {
            $0.id == model.selectedPeripheralID
        }
        let deviceIdentity = selectedCandidate?.displayIdentity
            ?? model.selectedPeripheralID.map(shortIdentity)

        return PopoverViewState(
            screen: resolvedScreen,
            firstConnectionPhase: FirstConnectionPresentation.resolve(
                started: model.hasStartedFirstConnection,
                bluetooth: model.bluetooth,
                selection: model.stationSelection,
                connection: model.connection,
                power: model.power,
                freshness: model.freshness,
                powerConfirmedInCurrentSession: model.powerConfirmedInCurrentSession,
                scanningFor: model.scanningFor,
                hasConnectionError: model.lastError != nil,
                isRescanning: model.isDeviceRescanInProgress
            ),
            isDeviceRescanInProgress: model.isDeviceRescanInProgress,
            deviceName: model.deviceName,
            deviceIdentity: deviceIdentity,
            bluetooth: model.bluetooth,
            connection: model.connection,
            power: model.power,
            powerConfirmedInCurrentSession: model.powerConfirmedInCurrentSession,
            freshness: model.freshness,
            snapshot: model.snapshot,
            presentation: model.presentation,
            batteryVisualState: model.lowBatteryVisualState,
            monitoringDetail: monitoringDetail,
            monitoringRecovery: monitoringRecovery,
            notificationReadiness: model.notificationReadiness,
            notificationActionResult: model.notificationActionResult,
            lastUpdate: model.lastUpdate,
            outageStartedAt: model.outageStartedAt,
            now: now,
            isVisible: model.isPopoverVisible,
            animationsEnabled: true,
            selectedID: model.selectedPeripheralID,
            stationCandidates: model.stationCandidates.map { candidate in
                PopoverStationChoice(
                    id: candidate.id,
                    name: stationName(candidate.advertisedName),
                    identity: candidate.displayIdentity,
                    isCurrent: candidate.id == model.selectedPeripheralID
                )
            },
            selectionMode: model.stationSelection.mode,
            canCancelDeviceSelection: model.canCancelDeviceSelection,
            loginItemStatus: model.loginItemStatus,
            loginItemError: model.loginItemError?.localized(using: model.localizer),
            launchAtLogin: model.launchAtLoginToggleValue,
            languagePreference: model.languagePreference,
            languageOptions: model.availableLanguageOptions,
            appearancePreference: model.appearancePreference
        )
    }

    private var resolvedScreen: PopoverScreen {
        switch route {
        case .chooser, .settings:
            return route
        case .normal, .setup:
            if !model.isFirstRunComplete { return .setup }
            if model.isSelectingDevice { return .chooser }
            return .normal
        }
    }

    private var monitoringRecovery: MonitoringRecoveryAction? {
        switch model.bluetooth {
        case .unauthorized:
            return .openBluetoothPrivacySettings
        case .poweredOff:
            return .openBluetoothControlSettings
        case .unknown, .resetting, .unsupported:
            return nil
        case .poweredOn:
            break
        }

        if model.connection == .disconnected { return .reconnect }
        if model.connection == .scanning, model.scanningFor >= 10 { return .chooseDevice }
        return nil
    }

    private var actions: PopoverActions {
        PopoverActions(
            showMain: {
                if model.canCancelDeviceSelection { model.cancelDeviceSelection() }
                route = .normal
            },
            showSettings: { route = .settings },
            startMonitoring: { model.startMonitoring() },
            beginDeviceSelection: {
                model.startMonitoring()
                route = .chooser
                if !model.isSelectingDevice { model.beginDeviceSelection() }
            },
            cancelDeviceSelection: {
                if model.canCancelDeviceSelection { model.cancelDeviceSelection() }
                route = .normal
            },
            rescanDevices: {
                model.startMonitoring()
                model.rescanDevices()
            },
            selectDevice: { id in
                model.startMonitoring()
                model.selectDevice(id)
                route = .normal
            },
            reconnect: {
                model.startMonitoring()
                model.reconnectAction?()
            },
            openBluetoothPrivacySettings: { model.openBluetoothPrivacySettingsAction?() },
            openBluetoothControlSettings: { model.openBluetoothControlSettingsAction?() },
            performNotificationAction: { action in
                switch action {
                case .none:
                    break
                case .refresh:
                    Task { await model.refreshNotificationHealth() }
                case .requestAuthorization:
                    model.requestNotificationAuthorization()
                case .openSystemSettings:
                    model.openNotificationSettings()
                }
            },
            testNotification: { model.testNotification() },
            clearNotificationResult: { model.clearNotificationActionResult() },
            setLaunchAtLogin: { enabled in model.setLaunchAtLogin(enabled) },
            openLoginItemSettings: { model.openLoginItemSettings() },
            setLanguage: { model.setLanguage($0) },
            setAppearance: { model.setAppearance($0) },
            copyDiagnostics: { model.copyDiagnostics() },
            showAbout: { NSApp.orderFrontStandardAboutPanel(nil) },
            quit: { NSApp.terminate(nil) }
        )
    }

    private func stationName(_ advertisedName: String) -> String {
        advertisedName.uppercased().hasPrefix("PR100V2")
            ? "Premium 100 V2"
            : (advertisedName.isEmpty ? "Premium 100 V2" : advertisedName)
    }

    private var monitoringDetail: String? {
        guard model.connection != .connected || model.freshness != .fresh,
              model.bluetooth == .poweredOn,
              model.connection == .disconnected,
              model.lastError == .bluetoothMayBeInUse
        else {
            return nil
        }
        return model.lastError?.localized(using: model.localizer)
    }

    private func shortIdentity(_ id: UUID) -> String {
        let raw = id.uuidString
        return "\(raw.prefix(4))…\(raw.suffix(4))"
    }
}
