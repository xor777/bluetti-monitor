import BluettiCore
import Foundation
import SwiftUI

enum PopoverScreen: Equatable {
    case normal
    case setup
    case chooser
    case settings
}

enum MonitoringRecoveryAction: Equatable {
    case openBluetoothPrivacySettings
    case openBluetoothControlSettings
    case reconnect
    case chooseDevice
}

struct PopoverStationChoice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let identity: String
    let isCurrent: Bool
}

struct PopoverViewState {
    let screen: PopoverScreen
    let firstConnectionPhase: FirstConnectionPhase
    let isDeviceRescanInProgress: Bool
    let deviceName: String
    let deviceIdentity: String?
    let bluetooth: BluetoothAvailability
    let connection: DeviceConnectionState
    let power: ExternalPowerState
    let powerConfirmedInCurrentSession: Bool
    let freshness: DataFreshness
    let snapshot: DeviceSnapshot
    let presentation: StatusPresentation
    let batteryVisualState: LowBatteryVisualState
    let monitoringDetail: String?
    let monitoringRecovery: MonitoringRecoveryAction?
    let notificationReadiness: NotificationReadinessPresentation
    let notificationActionResult: NotificationActionResult?
    let lastUpdate: Date?
    let outageStartedAt: Date?
    let now: Date
    let isVisible: Bool
    let animationsEnabled: Bool
    let selectedID: UUID?
    let stationCandidates: [PopoverStationChoice]
    let selectionMode: StationSelectionMode
    let canCancelDeviceSelection: Bool
    let loginItemStatus: LoginItemStatus
    let loginItemError: String?
    let launchAtLogin: Bool
    let languagePreference: LanguagePreference
    let languageOptions: [LanguageOption]
    let appearancePreference: AppearancePreference
}

struct PopoverActions {
    var showMain: () -> Void
    var showSettings: () -> Void
    var startMonitoring: () -> Void
    var beginDeviceSelection: () -> Void
    var cancelDeviceSelection: () -> Void
    var rescanDevices: () -> Void
    var selectDevice: (UUID) -> Void
    var reconnect: () -> Void
    var openBluetoothPrivacySettings: () -> Void
    var openBluetoothControlSettings: () -> Void
    var performNotificationAction: (NotificationReadinessAction) -> Void
    var testNotification: () -> Void
    var clearNotificationResult: () -> Void
    var setLaunchAtLogin: (Bool) -> Void
    var openLoginItemSettings: () -> Void
    var setLanguage: (LanguagePreference) -> Void
    var setAppearance: (AppearancePreference) -> Void
    var copyDiagnostics: () -> Void
    var showAbout: () -> Void
    var quit: () -> Void

    @MainActor
    static var none: PopoverActions { PopoverActions(
        showMain: {},
        showSettings: {},
        startMonitoring: {},
        beginDeviceSelection: {},
        cancelDeviceSelection: {},
        rescanDevices: {},
        selectDevice: { _ in },
        reconnect: {},
        openBluetoothPrivacySettings: {},
        openBluetoothControlSettings: {},
        performNotificationAction: { _ in },
        testNotification: {},
        clearNotificationResult: {},
        setLaunchAtLogin: { _ in },
        openLoginItemSettings: {},
        setLanguage: { _ in },
        setAppearance: { _ in },
        copyDiagnostics: {},
        showAbout: {},
        quit: {}
    ) }
}

struct PopoverContentView: View {
    let state: PopoverViewState
    let actions: PopoverActions
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch state.screen {
            case .normal:
                serviceHeader
                NormalMonitorView(state: state, actions: actions)
                    .padding(.top, 15)
            case .setup:
                setupHeader
                FirstConnectionView(state: state, actions: actions)
                    .padding(.top, 18)
            case .chooser:
                NavigationHeader(title: localizer.text("device.change.title"), action: actions.cancelDeviceSelection)
                DeviceChooserView(state: state, actions: actions)
                    .padding(.top, 18)
            case .settings:
                NavigationHeader(title: localizer.text("settings.title"), action: actions.showMain)
                SettingsView(state: state, actions: actions)
                    .padding(.top, 18)
            }
        }
        .padding(.horizontal, MonitorStyle.horizontalPadding)
        .padding(.vertical, MonitorStyle.verticalPadding)
        .frame(width: MonitorStyle.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
    }

    private var serviceHeader: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(state.connection == .connected ? MonitorStyle.accent : Color.secondary.opacity(0.55))
                .frame(width: 8, height: 8)
                .shadow(
                    color: state.connection == .connected ? MonitorStyle.accent.opacity(0.35) : .clear,
                    radius: 4
                )
                .accessibilityHidden(true)

            Text(state.deviceName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)

            if let identity = state.deviceIdentity {
                Text(identity)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.055), in: Capsule())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 10)
            ServiceMenu(actions: actions)
        }
    }

    private var setupHeader: some View {
        HStack {
            Text("Bluetti Monitor")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            SetupServiceMenu(actions: actions)
        }
    }
}

private struct SetupServiceMenu: View {
    let actions: PopoverActions
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        Menu {
            Button(localizer.text("actions.settings"), action: actions.showSettings)
            Divider()
            Button(localizer.text("actions.copyDiagnostics"), action: actions.copyDiagnostics)
            Button(localizer.text("actions.about"), action: actions.showAbout)
            Divider()
            Button(localizer.text("actions.quitApp"), action: actions.quit)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(localizer.text("accessibility.actions"))
    }
}

private struct ServiceMenu: View {
    let actions: PopoverActions
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        Menu {
            Button(localizer.text("actions.settings"), action: actions.showSettings)
            Button(localizer.text("actions.changeDevice"), action: actions.beginDeviceSelection)
            Divider()
            Button(localizer.text("actions.testNotification"), action: actions.testNotification)
            Button(localizer.text("actions.copyDiagnostics"), action: actions.copyDiagnostics)
            Divider()
            Button(localizer.text("actions.about"), action: actions.showAbout)
            Button(localizer.text("actions.quitApp"), action: actions.quit)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(localizer.text("accessibility.actions"))
    }
}

private struct NavigationHeader: View {
    let title: String
    let action: () -> Void
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(localizer.text("actions.back"))

            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
        }
    }
}

private struct NormalMonitorView: View {
    let state: PopoverViewState
    let actions: PopoverActions
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        VStack(alignment: .leading, spacing: MonitorStyle.sectionSpacing) {
            if state.presentation.tone != .good {
                MonitoringStatusView(state: state, actions: actions)
            }

            EnergyFlowView(
                snapshot: state.snapshot,
                presentation: state.presentation,
                power: state.power,
                powerConfirmedInCurrentSession: state.powerConfirmedInCurrentSession,
                freshness: state.freshness,
                batteryVisualState: state.batteryVisualState
            )

            NotificationReadinessView(state: state, actions: actions)

            if !state.notificationReadiness.canScheduleMonitoringAlerts || state.notificationActionResult != nil {
                Text(updateText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var updateText: String {
        guard let lastUpdate = state.lastUpdate else { return localizer.text("freshness.noData") }
        guard state.freshness != .fresh else { return localizer.text("freshness.current") }
        return localizer.format(
            "freshness.lastDataAgo",
            elapsedText(since: lastUpdate, now: state.now, localizer: localizer)
        )
    }
}

private struct MonitoringStatusView: View {
    let state: PopoverViewState
    let actions: PopoverActions
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(statusSubtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = state.monitoringDetail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let recovery = state.monitoringRecovery {
                Button(recoveryLabel(recovery)) {
                    perform(recovery)
                }
                .buttonStyle(.link)
                .font(.system(size: 12, weight: .medium))
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 28)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(statusColor.opacity(0.085), in: RoundedRectangle(cornerRadius: MonitorStyle.sectionRadius))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(statusColor)
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.leading, 12)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        guard state.batteryVisualState == .warning,
              let percent = state.snapshot.batteryPercent
        else {
            return state.presentation.title
        }
        return localizer.text(percent <= 10 ? "battery.critical" : "battery.low")
    }

    private var statusSubtitle: String {
        if state.batteryVisualState == .warning {
            let elapsed = state.outageStartedAt.map {
                elapsedText(since: $0, now: state.now, localizer: localizer)
            }
            let outage = elapsed.map { localizer.format("outage.withDuration", $0) }
                ?? localizer.text("outage.title")
            return state.snapshot.batteryPercent.map {
                $0 <= 10 ? localizer.format("outage.saveWork", outage) : outage
            }
                ?? outage
        }
        guard state.power == .offline, let startedAt = state.outageStartedAt else {
            return state.presentation.subtitle
        }
        return localizer.format(
            "status.withDuration",
            state.presentation.subtitle,
            elapsedText(since: startedAt, now: state.now, localizer: localizer)
        )
    }

    private var statusColor: Color {
        if state.batteryVisualState == .warning,
           let percent = state.snapshot.batteryPercent,
           percent <= 10
        {
            return .red
        }
        return MonitorStyle.color(for: state.presentation.tone)
    }

    private func recoveryLabel(_ action: MonitoringRecoveryAction) -> String {
        switch action {
        case .openBluetoothPrivacySettings, .openBluetoothControlSettings:
            localizer.text("actions.openBluetoothSettings")
        case .reconnect: localizer.text("actions.reconnect")
        case .chooseDevice: localizer.text("actions.chooseDevice")
        }
    }

    private func perform(_ action: MonitoringRecoveryAction) {
        switch action {
        case .openBluetoothPrivacySettings: actions.openBluetoothPrivacySettings()
        case .openBluetoothControlSettings: actions.openBluetoothControlSettings()
        case .reconnect: actions.reconnect()
        case .chooseDevice: actions.beginDeviceSelection()
        }
    }
}

private struct NotificationReadinessView: View {
    let state: PopoverViewState
    let actions: PopoverActions
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        if state.screen == .normal,
           state.notificationReadiness.canScheduleMonitoringAlerts,
           state.notificationActionResult == nil
        {
            Button(action: actions.showSettings) {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 10))
                    Text(healthyFooterText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .accessibilityLabel(localizer.format("accessibility.openSettingsFor", healthyFooterText))
        } else {
            fullReadiness
        }
    }

    private var healthyFooterText: String {
        let freshness: String
        if state.freshness == .fresh {
            freshness = localizer.text("freshness.current")
        } else if let lastUpdate = state.lastUpdate {
            freshness = localizer.format(
                "freshness.lastDataAgo",
                elapsedText(since: lastUpdate, now: state.now, localizer: localizer)
            )
        } else {
            freshness = localizer.text("freshness.noData")
        }
        return localizer.format("notifications.enabledSummary", freshness)
    }

    private var fullReadiness: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: notificationIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(notificationColor)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.notificationReadiness.title)
                        .font(.system(size: 13, weight: .medium))
                    Text(state.notificationReadiness.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
                notificationButton
            }

            if let result = state.notificationActionResult {
                NotificationResultView(result: result, clear: actions.clearNotificationResult)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: MonitorStyle.sectionRadius))
    }

    @ViewBuilder
    private var notificationButton: some View {
        switch state.notificationReadiness.action {
        case .requestAuthorization:
            Button(localizer.text("actions.allow")) {
                actions.performNotificationAction(.requestAuthorization)
            }
            .buttonStyle(.link)
            .font(.system(size: 12, weight: .medium))
        case .openSystemSettings:
            Button(localizer.text("settings.title")) {
                actions.performNotificationAction(.openSystemSettings)
            }
            .buttonStyle(.link)
            .font(.system(size: 12, weight: .medium))
        case .refresh:
            Button(localizer.text("actions.check")) {
                actions.performNotificationAction(.refresh)
            }
            .buttonStyle(.link)
            .font(.system(size: 12, weight: .medium))
        case .none:
            Button(localizer.text("actions.check"), action: actions.testNotification)
                .buttonStyle(.link)
                .font(.system(size: 12))
        }
    }

    private var notificationIcon: String {
        state.notificationReadiness.canScheduleMonitoringAlerts ? "bell.fill" : "bell.slash"
    }

    private var notificationColor: Color {
        state.notificationReadiness.canScheduleMonitoringAlerts ? MonitorStyle.accent : .orange
    }
}

private struct NotificationResultView: View {
    let result: NotificationActionResult
    let clear: () -> Void
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: clear) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(localizer.text("accessibility.dismissMessage"))
        }
    }

    private var message: String {
        switch result {
        case let .success(confirmation): confirmation.localized(using: localizer)
        case let .failure(error): error.localized(using: localizer)
        case let .unavailable(health):
            NotificationReadinessPresentation.make(health, localizer: localizer).detail
        }
    }

    private var symbol: String {
        switch result {
        case .success: "checkmark.circle.fill"
        case .failure, .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch result {
        case .success: MonitorStyle.accent
        case .failure, .unavailable: .orange
        }
    }
}

private struct FirstConnectionView: View {
    let state: PopoverViewState
    let actions: PopoverActions
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        VStack(alignment: .leading, spacing: MonitorStyle.sectionSpacing) {
            VStack(alignment: .leading, spacing: 5) {
                Text(localizer.text("setup.title"))
                    .font(.system(size: 23, weight: .semibold))
                Text(localizer.text("setup.detail"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            phaseContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch state.firstConnectionPhase {
        case .welcome:
            primaryButton(
                localizer.text("setup.findStation"),
                systemImage: "antenna.radiowaves.left.and.right",
                action: actions.startMonitoring
            )
        case .readyToConnect:
            selectedStationCard
            primaryButton(
                localizer.text("setup.connectStation"),
                systemImage: "link",
                action: actions.startMonitoring
            )
            changeStationButton
        case .startingBluetooth:
            progressCard(
                title: localizer.text("setup.startingBluetooth.title"),
                detail: localizer.text("setup.startingBluetooth.detail")
            )
        case let .searching(candidateCount):
            progressCard(
                title: localizer.text("setup.searching.title"),
                detail: candidateCount == 0
                    ? localizer.text("setup.searching.detail")
                    : localizer.format("setup.searching.found", candidateCount)
            )
        case .choosing:
            Text(localizer.text("setup.chooseInstruction"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            StationChoicesView(choices: state.stationCandidates, select: actions.selectDevice)
            Button(localizer.text("actions.searchAgain"), action: actions.rescanDevices)
                .buttonStyle(.link)
                .font(.system(size: 12))
        case .empty:
            EmptyDiscoveryView(showPhoneHint: true)
            primaryButton(
                localizer.text("actions.searchAgain"),
                systemImage: "arrow.clockwise",
                action: actions.rescanDevices
            )
        case .rescanning:
            progressCard(
                title: localizer.text("setup.rescanning.title"),
                detail: localizer.text("setup.rescanning.detail")
            )
        case .bluetoothUnauthorized:
            statusCard(
                symbol: "hand.raised.fill",
                color: .orange,
                title: localizer.text("setup.bluetoothUnauthorized.title"),
                detail: localizer.text("setup.bluetoothUnauthorized.detail")
            )
            primaryButton(
                localizer.text("actions.openBluetoothSettings"),
                systemImage: "gear",
                action: actions.openBluetoothPrivacySettings
            )
        case .bluetoothOff:
            statusCard(
                symbol: "antenna.radiowaves.left.and.right.slash",
                color: .orange,
                title: localizer.text("setup.bluetoothOff.title"),
                detail: localizer.text("setup.bluetoothOff.detail")
            )
            primaryButton(
                localizer.text("actions.openBluetoothSettings"),
                systemImage: "gear",
                action: actions.openBluetoothControlSettings
            )
        case .bluetoothUnsupported:
            statusCard(
                symbol: "exclamationmark.triangle.fill",
                color: .orange,
                title: localizer.text("setup.bluetoothUnsupported.title"),
                detail: localizer.text("setup.bluetoothUnsupported.detail")
            )
        case .bluetoothResetting:
            progressCard(
                title: localizer.text("setup.bluetoothResetting.title"),
                detail: localizer.text("setup.bluetoothResetting.detail")
            )
        case .findingSelectedStation:
            progressCard(
                title: localizer.text("setup.findingSelected.title"),
                detail: selectedStationDetail
            )
            changeStationButton
        case .selectedStationNotFound:
            statusCard(
                symbol: "externaldrive.badge.questionmark",
                color: .orange,
                title: localizer.text("setup.selectedNotFound.title"),
                detail: localizer.text("setup.selectedNotFound.detail")
            )
            recoveryButtons
        case .connecting:
            progressCard(
                title: localizer.text("setup.connecting.title"),
                detail: selectedStationDetail
            )
            changeStationButton
        case .waitingForTelemetry:
            progressCard(
                title: localizer.text("setup.connected.title"),
                detail: localizer.text("setup.connected.detail")
            )
            changeStationButton
        case .connectionFailed:
            statusCard(
                symbol: "exclamationmark.triangle.fill",
                color: .orange,
                title: localizer.text("setup.connectionFailed.title"),
                detail: state.monitoringDetail
                    ?? localizer.text("setup.connectionFailed.detail")
            )
            recoveryButtons
        case .ready:
            statusCard(
                symbol: "checkmark.circle.fill",
                color: MonitorStyle.accent,
                title: localizer.text("setup.ready.title"),
                detail: localizer.text("setup.ready.detail")
            )
        }
    }

    private var selectedStationCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 15))
                .foregroundStyle(MonitorStyle.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Premium 100 V2")
                    .font(.system(size: 13, weight: .medium))
                Text(state.deviceIdentity ?? localizer.text("setup.stationSelected"))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: MonitorStyle.sectionRadius))
    }

    private var changeStationButton: some View {
        Button(localizer.text("actions.chooseAnotherStation"), action: actions.beginDeviceSelection)
            .buttonStyle(.link)
            .font(.system(size: 12))
    }

    private var recoveryButtons: some View {
        HStack(spacing: 9) {
            Button(action: actions.reconnect) {
                Text(localizer.text("actions.retry"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(primaryActionForeground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        MonitorStyle.accent,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            Button(localizer.text("actions.chooseAnother"), action: actions.beginDeviceSelection)
                .buttonStyle(.bordered)
        }
    }

    private var selectedStationDetail: String {
        state.deviceIdentity.map { "Premium 100 V2 · \($0)" }
            ?? "Premium 100 V2"
    }

    private func primaryButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(primaryActionForeground)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    MonitorStyle.accent,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var primaryActionForeground: Color {
        colorScheme == .dark ? Color.black.opacity(0.9) : .white
    }

    private func progressCard(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: MonitorStyle.sectionRadius))
    }

    private func statusCard(
        symbol: String,
        color: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: MonitorStyle.sectionRadius))
    }
}

private struct DeviceChooserView: View {
    let state: PopoverViewState
    let actions: PopoverActions
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        VStack(alignment: .leading, spacing: MonitorStyle.sectionSpacing) {
            if BluetoothSettingsRecovery.destination(for: state.bluetooth) != nil {
                VStack(alignment: .leading, spacing: 7) {
                    Text(state.presentation.title)
                        .font(.system(size: 18, weight: .semibold))
                    Text(state.presentation.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button(localizer.text("actions.openBluetoothSettings"), action: openBluetoothRecovery)
                        .buttonStyle(.link)
                }
            } else if state.isDeviceRescanInProgress {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(localizer.text("setup.rescanning.title"))
                        .font(.system(size: 13))
                }
            } else if state.stationCandidates.isEmpty {
                if state.selectionMode == .initialDiscovery {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text(localizer.text("setup.searching.title"))
                            .font(.system(size: 13))
                    }
                } else {
                    EmptyDiscoveryView(showPhoneHint: state.bluetooth == .poweredOn)
                }
            } else {
                Text(chooserInstruction)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                StationChoicesView(choices: state.stationCandidates, select: actions.selectDevice)
            }

            HStack {
                Button(localizer.text("actions.searchAgain"), action: actions.rescanDevices)
                    .disabled(state.bluetooth != .poweredOn || state.isDeviceRescanInProgress)
                Spacer()
                if state.canCancelDeviceSelection {
                    Button(localizer.text("actions.cancel"), action: actions.cancelDeviceSelection)
                } else {
                    Button(localizer.text("actions.back"), action: actions.cancelDeviceSelection)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chooserInstruction: String {
        if state.selectedID != nil, state.connection == .connected {
            return localizer.text("chooser.instruction.currentContinues")
        }
        return localizer.text("chooser.instruction")
    }

    private func openBluetoothRecovery() {
        switch BluetoothSettingsRecovery.destination(for: state.bluetooth) {
        case .privacyPermission:
            actions.openBluetoothPrivacySettings()
        case .bluetoothControl:
            actions.openBluetoothControlSettings()
        case nil:
            break
        }
    }
}

private struct StationChoicesView: View {
    let choices: [PopoverStationChoice]
    let select: (UUID) -> Void
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                if index > 0 { Divider() }
                Button {
                    select(choice.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "externaldrive.connected.to.line.below")
                            .font(.system(size: 14))
                            .foregroundStyle(choice.isCurrent ? MonitorStyle.accent : Color.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(choice.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(choice.identity)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if choice.isCurrent {
                            Text(localizer.text("chooser.current"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(MonitorStyle.accent)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: MonitorStyle.sectionRadius))
        .overlay(
            RoundedRectangle(cornerRadius: MonitorStyle.sectionRadius)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct EmptyDiscoveryView: View {
    let showPhoneHint: Bool
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localizer.text("chooser.empty.title"))
                .font(.system(size: 17, weight: .semibold))
            Text(localizer.text("chooser.empty.detail"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if showPhoneHint {
                Label(
                    localizer.text("chooser.empty.phoneHint"),
                    systemImage: "iphone.slash"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
            }
        }
    }
}

private struct SettingsView: View {
    let state: PopoverViewState
    let actions: PopoverActions
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        VStack(alignment: .leading, spacing: MonitorStyle.sectionSpacing) {
            VStack(spacing: 10) {
                preferenceRow(title: localizer.text("settings.language.label")) {
                    Picker(
                        localizer.text("settings.language.label"),
                        selection: Binding(
                            get: { state.languagePreference },
                            set: { actions.setLanguage($0) }
                        )
                    ) {
                        Text(localizer.text("settings.language.system"))
                            .tag(LanguagePreference.system)
                        ForEach(state.languageOptions) { option in
                            Text(option.nativeName)
                                .tag(LanguagePreference.language(option.identifier))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                Divider()

                preferenceRow(title: localizer.text("settings.appearance.label")) {
                    Picker(
                        localizer.text("settings.appearance.label"),
                        selection: Binding(
                            get: { state.appearancePreference },
                            set: { actions.setAppearance($0) }
                        )
                    ) {
                        ForEach(AppearancePreference.allCases, id: \.self) { appearance in
                            Text(appearanceName(appearance)).tag(appearance)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
            .padding(11)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: MonitorStyle.sectionRadius))

            LoginItemRow(state: state, actions: actions)

            VStack(alignment: .leading, spacing: 8) {
                Text(localizer.text("settings.notifications"))
                    .font(.system(size: 13, weight: .semibold))
                NotificationReadinessView(state: state, actions: actions)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(localizer.text("settings.device"))
                    .font(.system(size: 13, weight: .semibold))
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.deviceName)
                            .font(.system(size: 13, weight: .medium))
                        Text(state.deviceIdentity ?? localizer.text("settings.device.notSelected"))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(localizer.text("settings.device.change"), action: actions.beginDeviceSelection)
                }
            }
            .padding(11)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: MonitorStyle.sectionRadius))

            Divider()
            HStack(spacing: 14) {
                Button(localizer.text("actions.copyDiagnostics"), action: actions.copyDiagnostics)
                Button(localizer.text("actions.about"), action: actions.showAbout)
                Spacer()
                Button(localizer.text("actions.quit"), action: actions.quit)
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func preferenceRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            content()
        }
    }

    private func appearanceName(_ appearance: AppearancePreference) -> String {
        switch appearance {
        case .system: localizer.text("settings.appearance.system")
        case .light: localizer.text("settings.appearance.light")
        case .dark: localizer.text("settings.appearance.dark")
        }
    }
}

private struct LoginItemRow: View {
    let state: PopoverViewState
    let actions: PopoverActions
    @Environment(\.appLocalizer) private var localizer

    @ViewBuilder
    var body: some View {
        if state.loginItemStatus == .unavailable {
            VStack(alignment: .leading, spacing: 3) {
                Text(localizer.text("login.title"))
                    .font(.system(size: 13, weight: .medium))
                Text(localizer.text("login.unavailable.detail"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .loginItemCard()
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Toggle(
                    isOn: Binding(
                        get: { state.launchAtLogin },
                        set: { value in actions.setLaunchAtLogin(value) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizer.text("login.toggle"))
                            .font(.system(size: 13, weight: .medium))
                        Text(loginDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(loginDetailColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .disabled(state.loginItemStatus == .unknown)

                if let error = state.loginItemError,
                   !error.isEmpty,
                   error != loginDetail
                {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if state.loginItemStatus == .requiresApproval {
                    Button(localizer.text("login.openSettings"), action: actions.openLoginItemSettings)
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
            .loginItemCard()
        }
    }

    private var loginDetail: String {
        switch state.loginItemStatus {
        case .unknown: localizer.text("login.status.unknown")
        case .disabled: localizer.text("login.status.disabled")
        case .enabled: localizer.text("login.status.enabled")
        case .requiresApproval: localizer.text("login.status.requiresApproval")
        case .unavailable: localizer.text("login.status.unavailable")
        }
    }

    private var loginDetailColor: Color {
        state.loginItemStatus == .requiresApproval ? .orange : .secondary
    }
}

private extension View {
    func loginItemCard() -> some View {
        padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: MonitorStyle.sectionRadius)
            )
    }
}

private func elapsedText(since date: Date, now: Date, localizer: AppLocalizer) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 60 { return localizer.text("duration.lessThanMinute") }
    let minutes = seconds / 60
    if minutes < 60 { return localizer.minutes(minutes) }
    let hours = minutes / 60
    let remainder = minutes % 60
    return remainder == 0
        ? localizer.hours(hours)
        : "\(localizer.hours(hours)) \(localizer.minutes(remainder))"
}

private func shortIdentity(_ id: UUID) -> String {
    let raw = id.uuidString
    return "\(raw.prefix(4))…\(raw.suffix(4))"
}
