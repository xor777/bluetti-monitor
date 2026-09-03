public struct MenuBarPresentation: Equatable, Sendable {
    public enum Icon: Equatable, Sendable {
        case online
        case backup
        case stale
        case unavailable
        case searching
    }

    public struct Input: Equatable, Sendable {
        public var bluetooth: BluetoothAvailability
        public var connection: DeviceConnectionState
        public var power: ExternalPowerState
        public var freshness: DataFreshness

        public init(
            bluetooth: BluetoothAvailability = .unknown,
            connection: DeviceConnectionState = .disconnected,
            power: ExternalPowerState = .unknown,
            freshness: DataFreshness = .lost
        ) {
            self.bluetooth = bluetooth
            self.connection = connection
            self.power = power
            self.freshness = freshness
        }
    }

    public let title: String
    public let icon: Icon

    public static func make(_ input: Input) -> Self {
        guard input.bluetooth == .poweredOn else {
            return .init(title: "", icon: .unavailable)
        }

        if input.freshness == .stale {
            return .init(title: "", icon: .stale)
        }

        guard input.connection == .connected else {
            if input.connection == .disconnected, input.freshness == .lost {
                return .init(title: "", icon: .unavailable)
            }
            return .init(title: "", icon: .searching)
        }

        switch input.power {
        case .online:
            return .init(title: "", icon: .online)
        case .offline:
            return .init(title: "", icon: .backup)
        case .unknown:
            return .init(title: "", icon: .searching)
        }
    }
}
