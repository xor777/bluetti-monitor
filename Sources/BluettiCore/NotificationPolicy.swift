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
        switch self {
        case .powerLost: "Питание пропало"
        case .powerAbsent: "Питание отсутствует"
        case .powerRestored: "Питание восстановлено"
        case .lowBattery: "Низкий заряд станции"
        case .connectionLost: "Связь с устройством потеряна"
        case .connectionRestored: "Связь восстановлена"
        case .test: "Тест уведомления"
        }
    }

    public var body: String? {
        switch self {
        case let .powerLost(batteryPercent), let .powerAbsent(batteryPercent):
            batteryPercent.map { "Заряд станции: \($0)%" }
        case let .lowBattery(batteryPercent):
            "Заряд станции: \(batteryPercent)%. Сохраните работу."
        case .test:
            "Если вы видите этот баннер, macOS показывает уведомления."
        case .powerRestored, .connectionLost, .connectionRestored:
            nil
        }
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

    public static func make(_ health: NotificationHealth) -> NotificationReadinessPresentation {
        switch health {
        case .unknown:
            NotificationReadinessPresentation(
                title: "Уведомления не проверены",
                detail: "Статус macOS пока неизвестен",
                action: .refresh,
                canScheduleMonitoringAlerts: false
            )
        case .notDetermined:
            NotificationReadinessPresentation(
                title: "Уведомления не настроены",
                detail: "Разрешите уведомления, чтобы узнать об отключении питания",
                action: .requestAuthorization,
                canScheduleMonitoringAlerts: false
            )
        case .denied:
            NotificationReadinessPresentation(
                title: "Уведомления запрещены",
                detail: "Разрешите их в настройках macOS",
                action: .openSystemSettings,
                canScheduleMonitoringAlerts: false
            )
        case .alertsDisabled:
            NotificationReadinessPresentation(
                title: "Баннеры уведомлений выключены",
                detail: "Включите баннеры в настройках macOS",
                action: .openSystemSettings,
                canScheduleMonitoringAlerts: false
            )
        case .available:
            NotificationReadinessPresentation(
                title: "Уведомления готовы",
                detail: "macOS может показать баннеры",
                action: .none,
                canScheduleMonitoringAlerts: true
            )
        }
    }
}
