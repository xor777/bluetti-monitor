import Foundation

public enum NotificationEvent: Equatable, Sendable {
    case powerLost(batteryPercent: Int?)
    case powerAbsent(batteryPercent: Int?)
    case powerRestored
    case lowBattery(batteryPercent: Int)
    case connectionLost
    case connectionRestored
    case test

    public var title: String {
        content(using: AppLocalizer()).title
    }

    public var body: String? {
        content(using: AppLocalizer()).body
    }

    public func content(using localizer: AppLocalizer) -> LocalizedNotificationContent {
        let titleKey: String
        switch self {
        case .powerLost: titleKey = "notification.powerLost.title"
        case .powerAbsent: titleKey = "notification.powerAbsent.title"
        case .powerRestored: titleKey = "notification.powerRestored.title"
        case .lowBattery: titleKey = "notification.lowBattery.title"
        case .connectionLost: titleKey = "notification.connectionLost.title"
        case .connectionRestored: titleKey = "notification.connectionRestored.title"
        case .test: titleKey = "notification.test.title"
        }

        let body: String?
        switch self {
        case let .powerLost(batteryPercent), let .powerAbsent(batteryPercent):
            body = batteryPercent.map { localizer.format("notification.stationCharge", Int64($0)) }
        case let .lowBattery(batteryPercent):
            body = localizer.format("notification.lowBattery.body", Int64(batteryPercent))
        case .test:
            body = localizer.text("notification.test.body")
        case .powerRestored, .connectionLost, .connectionRestored:
            body = nil
        }
        return LocalizedNotificationContent(title: localizer.text(titleKey), body: body)
    }

    public var playsSound: Bool {
        switch self {
        case .powerLost, .powerAbsent, .lowBattery, .connectionLost:
            true
        case .powerRestored, .connectionRestored, .test:
            false
        }
    }
}

public struct LocalizedNotificationContent: Equatable, Sendable {
    public let title: String
    public let body: String?

    public init(title: String, body: String?) {
        self.title = title
        self.body = body
    }
}

public struct NotificationPolicy: Sendable {
    private var hasEverBeenReady = false
    private var lossWasNotified = false

    public init() {}

    public mutating func handle(
        _ transition: PowerTransition,
        batteryPercent: Int? = nil
    ) -> NotificationEvent? {
        switch transition {
        case .initial(.offline): .powerAbsent(batteryPercent: batteryPercent)
        case .initial: nil
        case .changed(from: .online, to: .offline): .powerLost(batteryPercent: batteryPercent)
        case .changed(from: .offline, to: .online): .powerRestored
        case .changed: nil
        }
    }

    public mutating func monitoringReady() -> NotificationEvent? {
        if !hasEverBeenReady {
            hasEverBeenReady = true
            lossWasNotified = false
            return nil
        }
        guard lossWasNotified else { return nil }
        lossWasNotified = false
        return .connectionRestored
    }

    public mutating func monitoringLost() -> NotificationEvent? {
        guard hasEverBeenReady, !lossWasNotified else { return nil }
        lossWasNotified = true
        return .connectionLost
    }

    public mutating func resetForDeviceChange() {
        hasEverBeenReady = false
        lossWasNotified = false
    }
}

public struct LowBatteryAlertInput: Equatable, Sendable {
    public var power: ExternalPowerState
    public var powerConfirmedInCurrentSession: Bool
    public var batteryPercent: Int?
    public var batteryFreshness: DataFreshness
    public var batteryObservedInCurrentSession: Bool

    public init(
        power: ExternalPowerState,
        powerConfirmedInCurrentSession: Bool,
        batteryPercent: Int?,
        batteryFreshness: DataFreshness,
        batteryObservedInCurrentSession: Bool
    ) {
        self.power = power
        self.powerConfirmedInCurrentSession = powerConfirmedInCurrentSession
        self.batteryPercent = batteryPercent
        self.batteryFreshness = batteryFreshness
        self.batteryObservedInCurrentSession = batteryObservedInCurrentSession
    }

    public var validFreshBatteryPercent: Int? {
        guard batteryObservedInCurrentSession,
              batteryFreshness == .fresh,
              let batteryPercent,
              (0...100).contains(batteryPercent)
        else {
            return nil
        }
        return batteryPercent
    }
}

public enum LowBatteryVisualState: Equatable, Sendable {
    case unavailable
    case normal
    case warning
}

public struct LowBatteryAlertPolicy: Sendable {
    private var notificationSentInEpisode = false

    public init() {}

    public mutating func evaluate(_ input: LowBatteryAlertInput) -> NotificationEvent? {
        if input.powerConfirmedInCurrentSession, input.power == .online {
            notificationSentInEpisode = false
        }
        if let batteryPercent = input.validFreshBatteryPercent, batteryPercent > 25 {
            notificationSentInEpisode = false
        }

        guard input.powerConfirmedInCurrentSession,
              input.power == .offline,
              let batteryPercent = input.validFreshBatteryPercent,
              batteryPercent <= 20,
              !notificationSentInEpisode
        else {
            return nil
        }
        notificationSentInEpisode = true
        return .lowBattery(batteryPercent: batteryPercent)
    }

    public mutating func resetForDeviceChange() {
        notificationSentInEpisode = false
    }

    public static func visualState(_ input: LowBatteryAlertInput) -> LowBatteryVisualState {
        guard let batteryPercent = input.validFreshBatteryPercent else { return .unavailable }
        guard input.powerConfirmedInCurrentSession, input.power == .offline else { return .normal }
        return batteryPercent <= 20 ? .warning : .normal
    }
}

public enum NotificationReadinessAction: Equatable, Sendable {
    case none
    case refresh
    case requestAuthorization
    case openSystemSettings
}

public struct NotificationReadinessPresentation: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let action: NotificationReadinessAction
    public let canScheduleMonitoringAlerts: Bool

    public static func make(
        _ health: NotificationHealth,
        localizer: AppLocalizer = AppLocalizer()
    ) -> NotificationReadinessPresentation {
        switch health {
        case .unknown:
            NotificationReadinessPresentation(
                title: localizer.text("notifications.readiness.unknown.title"),
                detail: localizer.text("notifications.readiness.unknown.detail"),
                action: .refresh,
                canScheduleMonitoringAlerts: false
            )
        case .notDetermined:
            NotificationReadinessPresentation(
                title: localizer.text("notifications.readiness.notDetermined.title"),
                detail: localizer.text("notifications.readiness.notDetermined.detail"),
                action: .requestAuthorization,
                canScheduleMonitoringAlerts: false
            )
        case .denied:
            NotificationReadinessPresentation(
                title: localizer.text("notifications.readiness.denied.title"),
                detail: localizer.text("notifications.readiness.denied.detail"),
                action: .openSystemSettings,
                canScheduleMonitoringAlerts: false
            )
        case .alertsDisabled:
            NotificationReadinessPresentation(
                title: localizer.text("notifications.readiness.alertsDisabled.title"),
                detail: localizer.text("notifications.readiness.alertsDisabled.detail"),
                action: .openSystemSettings,
                canScheduleMonitoringAlerts: false
            )
        case .available:
            NotificationReadinessPresentation(
                title: localizer.text("notifications.readiness.available.title"),
                detail: localizer.text("notifications.readiness.available.detail"),
                action: .none,
                canScheduleMonitoringAlerts: true
            )
        }
    }
}
