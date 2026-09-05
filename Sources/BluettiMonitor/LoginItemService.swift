import Foundation
import ServiceManagement

enum LoginItemStatus: Equatable, Sendable {
    case unknown
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LoginItemManaging: AnyObject {
    func currentStatus() -> LoginItemStatus
    func setEnabled(_ enabled: Bool) throws -> LoginItemStatus
    func openSystemSettings()
}

@MainActor
final class LoginItemService: LoginItemManaging {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    func currentStatus() -> LoginItemStatus {
        status(from: service.status)
    }

    func setEnabled(_ enabled: Bool) throws -> LoginItemStatus {
        if enabled {
            switch service.status {
            case .enabled, .requiresApproval:
                return currentStatus()
            case .notRegistered:
                try service.register()
            case .notFound:
                throw LoginItemServiceError.serviceUnavailable
            @unknown default:
                throw LoginItemServiceError.serviceUnavailable
            }
        } else {
            switch service.status {
            case .notRegistered:
                return .disabled
            case .enabled, .requiresApproval:
                try service.unregister()
            case .notFound:
                throw LoginItemServiceError.serviceUnavailable
            @unknown default:
                throw LoginItemServiceError.serviceUnavailable
            }
        }
        return currentStatus()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func status(from value: SMAppService.Status) -> LoginItemStatus {
        switch value {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unknown
        }
    }
}

private enum LoginItemServiceError: LocalizedError {
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            "Open at Login is unavailable"
        }
    }
}
