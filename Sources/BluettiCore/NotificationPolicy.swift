import Foundation

public enum NotificationEvent: Equatable, Sendable {
    case powerLost
    case powerAbsent
    case powerRestored
    case connectionLost
    case connectionRestored
    case test

    public var text: String {
        switch self {
        case .powerLost: "Питание пропало"
        case .powerAbsent: "Питание отсутствует"
        case .powerRestored: "Питание восстановлено"
        case .connectionLost: "Связь с устройством потеряна"
        case .connectionRestored: "Связь восстановлена"
        case .test: "Уведомления работают"
        }
    }

    public var playsSound: Bool {
        self == .powerLost || self == .powerAbsent || self == .connectionLost
    }
}

public struct NotificationPolicy: Sendable {
    private var hasEverBeenReady = false
    private var lossWasNotified = false

    public init() {}

    public mutating func handle(_ transition: PowerTransition) -> NotificationEvent? {
        switch transition {
        case .initial(.offline): .powerAbsent
        case .initial: nil
        case .changed(from: .online, to: .offline): .powerLost
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
}
