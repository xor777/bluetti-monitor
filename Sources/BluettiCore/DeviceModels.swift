import Foundation

public enum BluetoothAvailability: Equatable, Sendable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

public enum DeviceConnectionState: Equatable, Sendable {
    case scanning
    case connecting
    case connected
    case disconnected
}

public enum ExternalPowerState: Equatable, Sendable {
    case unknown
    case online
    case offline
}

public enum DataFreshness: Equatable, Sendable {
    case fresh
    case stale
    case lost
}

public enum NotificationHealth: Equatable, Sendable {
    case unknown
    case notDetermined
    case denied
    case alertsDisabled
    case available

    public var canScheduleMonitoringAlerts: Bool {
        self == .available
    }

    public var needsAuthorizationRequest: Bool {
        self == .notDetermined
    }

    public var needsSystemSettings: Bool {
        self == .denied || self == .alertsDisabled
    }
}

public enum RemainingTimeUpdate: Equatable, Sendable {
    case available(minutes: Int, isCapped: Bool)
    case unavailable(raw: Int)

    public var rawValue: Int {
        switch self {
        case let .available(minutes, _), let .unavailable(minutes):
            return minutes
        }
    }
}

public struct TelemetryPatch: Equatable, Sendable {
    public var model: String?
    public var batteryPercent: Int?
    public var remainingTime: RemainingTimeUpdate?
    public var acInputVoltage: Double?
    public var acInputPower: Int?
    public var acOutputPower: Int?
    public var dcInputPower: Int?
    public var dcOutputPower: Int?

    public init(
        model: String? = nil,
        batteryPercent: Int? = nil,
        remainingTime: RemainingTimeUpdate? = nil,
        acInputVoltage: Double? = nil,
        acInputPower: Int? = nil,
        acOutputPower: Int? = nil,
        dcInputPower: Int? = nil,
        dcOutputPower: Int? = nil
    ) {
        self.model = model
        self.batteryPercent = batteryPercent
        self.remainingTime = remainingTime
        self.acInputVoltage = acInputVoltage
        self.acInputPower = acInputPower
        self.acOutputPower = acOutputPower
        self.dcInputPower = dcInputPower
        self.dcOutputPower = dcOutputPower
    }
}

public struct DeviceSnapshot: Equatable, Sendable {
    public var model: String?
    public var batteryPercent: Int?
    public var acInputVoltage: Double?
    public var acInputPower: Int?
    public var acOutputPower: Int?
    public var dcInputPower: Int?
    public var dcOutputPower: Int?
    public var remainingTimeMinutes: Int?
    public var remainingTimeIsCapped: Bool

    public init(
        model: String? = nil,
        batteryPercent: Int? = nil,
        acInputVoltage: Double? = nil,
        acInputPower: Int? = nil,
        acOutputPower: Int? = nil,
        dcInputPower: Int? = nil,
        dcOutputPower: Int? = nil,
        remainingTimeMinutes: Int? = nil,
        remainingTimeIsCapped: Bool = false
    ) {
        self.model = model
        self.batteryPercent = batteryPercent
        self.acInputVoltage = acInputVoltage
        self.acInputPower = acInputPower
        self.acOutputPower = acOutputPower
        self.dcInputPower = dcInputPower
        self.dcOutputPower = dcOutputPower
        self.remainingTimeMinutes = remainingTimeMinutes
        self.remainingTimeIsCapped = remainingTimeIsCapped
    }

    public mutating func apply(_ patch: TelemetryPatch) {
        if let model = patch.model { self.model = model }
        if let batteryPercent = patch.batteryPercent { self.batteryPercent = batteryPercent }
        if let acInputVoltage = patch.acInputVoltage { self.acInputVoltage = acInputVoltage }
        if let acInputPower = patch.acInputPower { self.acInputPower = acInputPower }
        if let acOutputPower = patch.acOutputPower { self.acOutputPower = acOutputPower }
        if let dcInputPower = patch.dcInputPower { self.dcInputPower = dcInputPower }
        if let dcOutputPower = patch.dcOutputPower { self.dcOutputPower = dcOutputPower }
        if let remainingTime = patch.remainingTime {
            switch remainingTime {
            case let .available(minutes, isCapped):
                remainingTimeMinutes = minutes
                remainingTimeIsCapped = isCapped
            case .unavailable:
                clearRemainingTime()
            }
        }
    }

    public mutating func clearRemainingTime() {
        remainingTimeMinutes = nil
        remainingTimeIsCapped = false
    }

    public mutating func clearTelemetryForNewSession() {
        batteryPercent = nil
        acInputVoltage = nil
        acInputPower = nil
        acOutputPower = nil
        dcInputPower = nil
        dcOutputPower = nil
        clearRemainingTime()
    }
}
