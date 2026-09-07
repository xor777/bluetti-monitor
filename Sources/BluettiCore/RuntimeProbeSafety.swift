public enum RuntimeProbeFailure: Equatable, Sendable {
    case timedOut
    case modbusException(UInt8)
}

public enum RuntimeProbeFailureAction: Equatable, Sendable {
    case propagate
    case disableAndContinue
    case disableAndReconnect
}

public struct RuntimeProbeSafety: Sendable {
    public private(set) var isEnabled: Bool
    private let probeRead: ModbusRead

    public init(enabled: Bool, probeRead: ModbusRead) {
        isEnabled = enabled
        self.probeRead = probeRead
    }

    public mutating func handle(
        _ failure: RuntimeProbeFailure,
        pendingRead: ModbusRead?
    ) -> RuntimeProbeFailureAction {
        guard isEnabled else { return .propagate }

        switch failure {
        case .timedOut:
            isEnabled = false
            return .disableAndReconnect
        case .modbusException where pendingRead == probeRead:
            isEnabled = false
            return .disableAndContinue
        case .modbusException:
            return .propagate
        }
    }
}
