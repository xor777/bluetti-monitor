import Foundation

public enum FirstConnectionPhase: Equatable, Sendable {
    case welcome
    case readyToConnect
    case startingBluetooth
    case searching(candidateCount: Int)
    case choosing
    case empty
    case bluetoothUnauthorized
    case bluetoothOff
    case bluetoothUnsupported
    case bluetoothResetting
    case findingSelectedStation
    case selectedStationNotFound
    case connecting
    case waitingForTelemetry
    case connectionFailed
    case rescanning
    case ready
}

public enum BluetoothSettingsDestination: Equatable, Sendable {
    case privacyPermission
    case bluetoothControl
}

public enum BluetoothSettingsRecovery {
    public static func destination(
        for availability: BluetoothAvailability
    ) -> BluetoothSettingsDestination? {
        switch availability {
        case .unauthorized:
            .privacyPermission
        case .poweredOff:
            .bluetoothControl
        case .unknown, .resetting, .unsupported, .poweredOn:
            nil
        }
    }
}

public enum FirstConnectionPresentation {
    public static func resolve(
        started: Bool,
        bluetooth: BluetoothAvailability,
        selection: StationSelectionSnapshot,
        connection: DeviceConnectionState,
        power: ExternalPowerState,
        freshness: DataFreshness,
        powerConfirmedInCurrentSession: Bool,
        scanningFor: TimeInterval,
        hasConnectionError: Bool,
        isRescanning: Bool
    ) -> FirstConnectionPhase {
        guard started else {
            return selection.selectedID == nil ? .welcome : .readyToConnect
        }

        switch bluetooth {
        case .unknown:
            return .startingBluetooth
        case .resetting:
            return .bluetoothResetting
        case .unsupported:
            return .bluetoothUnsupported
        case .unauthorized:
            return .bluetoothUnauthorized
        case .poweredOff:
            return .bluetoothOff
        case .poweredOn:
            break
        }

        if isRescanning { return .rescanning }

        if selection.mode == .choosing {
            return selection.candidates.isEmpty ? .empty : .choosing
        }

        guard selection.selectedID != nil else {
            return .searching(candidateCount: selection.candidates.count)
        }

        if FirstRunReadiness.isSatisfied(
            selectedID: selection.selectedID,
            connection: connection,
            power: power,
            freshness: freshness,
            powerConfirmedInCurrentSession: powerConfirmedInCurrentSession
        ) {
            return .ready
        }

        switch connection {
        case .connecting:
            return .connecting
        case .connected:
            return .waitingForTelemetry
        case .scanning:
            return scanningFor >= 10
                ? .selectedStationNotFound
                : .findingSelectedStation
        case .disconnected:
            return hasConnectionError ? .connectionFailed : .findingSelectedStation
        }
    }
}
