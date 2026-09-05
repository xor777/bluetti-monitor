import Foundation

public struct StatusContext: Equatable, Sendable {
    public var bluetooth: BluetoothAvailability
    public var connection: DeviceConnectionState
    public var power: ExternalPowerState
    public var freshness: DataFreshness
    public var powerConfirmedInCurrentSession: Bool
    public var scanningFor: TimeInterval
    public var inputPower: Int?
    public var outputPower: Int?

    public init(
        bluetooth: BluetoothAvailability = .unknown,
        connection: DeviceConnectionState = .disconnected,
        power: ExternalPowerState = .unknown,
        freshness: DataFreshness = .lost,
        powerConfirmedInCurrentSession: Bool = false,
        scanningFor: TimeInterval = 0,
        inputPower: Int? = nil,
        outputPower: Int? = nil
    ) {
        self.bluetooth = bluetooth
        self.connection = connection
        self.power = power
        self.freshness = freshness
        self.powerConfirmedInCurrentSession = powerConfirmedInCurrentSession
        self.scanningFor = scanningFor
        self.inputPower = inputPower
        self.outputPower = outputPower
    }
}

public enum StatusTone: Equatable, Sendable {
    case neutral
    case good
    case warning
    case unavailable
}

public struct StatusPresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let tone: StatusTone
    public let inputFlowActive: Bool
    public let outputFlowActive: Bool

    public static func make(
        _ context: StatusContext,
        localizer: AppLocalizer = AppLocalizer()
    ) -> StatusPresentation {
        switch context.bluetooth {
        case .poweredOff:
            return inactive("status.bluetooth.off.title", "status.bluetooth.off.subtitle", .unavailable, localizer)
        case .unauthorized:
            return inactive("status.bluetooth.unauthorized.title", "status.bluetooth.unauthorized.subtitle", .unavailable, localizer)
        case .unsupported:
            return inactive("status.bluetooth.unsupported.title", "status.bluetooth.unsupported.subtitle", .unavailable, localizer)
        case .resetting:
            return inactive("status.bluetooth.resetting.title", "status.bluetooth.resetting.subtitle", .neutral, localizer)
        case .unknown:
            return inactive("status.bluetooth.unknown.title", "status.bluetooth.unknown.subtitle", .neutral, localizer)
        case .poweredOn:
            break
        }

        switch context.connection {
        case .scanning:
            if context.scanningFor >= 10 {
                return inactive("status.scanning.notFound.title", "status.scanning.notFound.subtitle", .unavailable, localizer)
            }
            return inactive("status.scanning.title", "status.scanning.subtitle", .neutral, localizer)
        case .connecting:
            return inactive("status.connecting.title", "status.connecting.subtitle", .neutral, localizer)
        case .disconnected:
            return inactive("status.disconnected.title", "status.disconnected.subtitle", .unavailable, localizer)
        case .connected:
            break
        }

        if context.freshness == .stale {
            return inactive("status.stale.title", "status.stale.subtitle", .warning, localizer)
        }
        if context.freshness == .lost {
            return inactive("status.disconnected.title", "status.disconnected.subtitle", .unavailable, localizer)
        }
        guard context.powerConfirmedInCurrentSession else {
            return inactive("status.loading.title", "status.loading.subtitle", .neutral, localizer)
        }

        switch context.power {
        case .online:
            return StatusPresentation(
                title: localizer.text("status.online.title"),
                subtitle: localizer.text("status.online.subtitle"),
                tone: .good,
                inputFlowActive: (context.inputPower ?? 0) > 1,
                outputFlowActive: (context.outputPower ?? 0) > 1
            )
        case .offline:
            let underLoad = (context.outputPower ?? 0) > 1
            return StatusPresentation(
                title: localizer.text(underLoad ? "status.backup.title" : "status.offline.title"),
                subtitle: localizer.text(underLoad ? "status.backup.subtitle" : "status.offline.subtitle"),
                tone: .warning,
                inputFlowActive: false,
                outputFlowActive: underLoad
            )
        case .unknown:
            return inactive("status.loading.title", "status.loading.subtitle", .neutral, localizer)
        }
    }

    private static func inactive(
        _ titleKey: String,
        _ subtitleKey: String,
        _ tone: StatusTone,
        _ localizer: AppLocalizer
    ) -> StatusPresentation {
        StatusPresentation(
            title: localizer.text(titleKey),
            subtitle: localizer.text(subtitleKey),
            tone: tone,
            inputFlowActive: false,
            outputFlowActive: false
        )
    }
}
