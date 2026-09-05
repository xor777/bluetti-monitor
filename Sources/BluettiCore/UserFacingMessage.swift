import Foundation

public enum UserFacingError: Equatable, Sendable {
    case bluetoothMayBeInUse
    case protocolFailure(String)
    case deviceDidNotRespond
    case deviceStoppedResponding
    case connectionTimedOut
    case notificationSchedulingFailed(String)
    case notificationPermissionFailed(String)
    case system(String)

    public func localized(using localizer: AppLocalizer) -> String {
        switch self {
        case .bluetoothMayBeInUse:
            localizer.text("error.bluetoothMayBeInUse")
        case let .protocolFailure(detail):
            localizer.format("error.protocolFailure", detail)
        case .deviceDidNotRespond:
            localizer.text("error.deviceDidNotRespond")
        case .deviceStoppedResponding:
            localizer.text("error.deviceStoppedResponding")
        case .connectionTimedOut:
            localizer.text("error.connectionTimedOut")
        case let .notificationSchedulingFailed(detail):
            localizer.format("error.notificationSchedulingFailed", detail)
        case let .notificationPermissionFailed(detail):
            localizer.format("error.notificationPermissionFailed", detail)
        case let .system(detail):
            detail
        }
    }

    public var diagnosticDetail: String {
        switch self {
        case .bluetoothMayBeInUse: "bluetoothMayBeInUse"
        case let .protocolFailure(detail): "protocolFailure: \(detail)"
        case .deviceDidNotRespond: "deviceDidNotRespond"
        case .deviceStoppedResponding: "deviceStoppedResponding"
        case .connectionTimedOut: "connectionTimedOut"
        case let .notificationSchedulingFailed(detail),
             let .notificationPermissionFailed(detail),
             let .system(detail): detail
        }
    }
}

public enum UserFacingConfirmation: Equatable, Sendable {
    case notificationScheduled
    case notificationsAllowed

    public func localized(using localizer: AppLocalizer) -> String {
        switch self {
        case .notificationScheduled:
            localizer.text("confirmation.notificationScheduled")
        case .notificationsAllowed:
            localizer.text("confirmation.notificationsAllowed")
        }
    }
}
