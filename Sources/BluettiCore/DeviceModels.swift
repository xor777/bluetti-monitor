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

public struct TelemetryPatch: Equatable, Sendable {
    public var model: String?
    public var batteryPercent: Int?
    public var acInputVoltage: Double?
    public var acInputPower: Int?
    public var acOutputPower: Int?

    public init(
        model: String? = nil,
        batteryPercent: Int? = nil,
        acInputVoltage: Double? = nil,
        acInputPower: Int? = nil,
        acOutputPower: Int? = nil
    ) {
        self.model = model
        self.batteryPercent = batteryPercent
        self.acInputVoltage = acInputVoltage
        self.acInputPower = acInputPower
        self.acOutputPower = acOutputPower
    }
}

public struct DeviceSnapshot: Equatable, Sendable {
    public var model: String?
    public var batteryPercent: Int?
    public var acInputVoltage: Double?
    public var acInputPower: Int?
    public var acOutputPower: Int?

    public init(
        model: String? = nil,
        batteryPercent: Int? = nil,
        acInputVoltage: Double? = nil,
        acInputPower: Int? = nil,
        acOutputPower: Int? = nil
    ) {
        self.model = model
        self.batteryPercent = batteryPercent
        self.acInputVoltage = acInputVoltage
        self.acInputPower = acInputPower
        self.acOutputPower = acOutputPower
    }

    public mutating func apply(_ patch: TelemetryPatch) {
        if let model = patch.model { self.model = model }
        if let batteryPercent = patch.batteryPercent { self.batteryPercent = batteryPercent }
        if let acInputVoltage = patch.acInputVoltage { self.acInputVoltage = acInputVoltage }
        if let acInputPower = patch.acInputPower { self.acInputPower = acInputPower }
        if let acOutputPower = patch.acOutputPower { self.acOutputPower = acOutputPower }
    }

    public mutating func clearTelemetryForNewSession() {
        batteryPercent = nil
        acInputVoltage = nil
        acInputPower = nil
        acOutputPower = nil
    }
}
