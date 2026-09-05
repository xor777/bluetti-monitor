import BluettiCore
import Foundation

func firstConnectionPresentationTests() -> [TestCase] {
    let current = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let second = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    let choices = [
        StationCandidate(id: current, advertisedName: "PR100V2-HOME-41"),
        StationCandidate(id: second, advertisedName: "PR100V2-OFFICE-2A"),
    ]

    func phase(
        started: Bool = true,
        bluetooth: BluetoothAvailability = .poweredOn,
        selection: StationSelectionSnapshot = .init(
            selectedID: nil,
            candidates: [],
            mode: .initialDiscovery
        ),
        connection: DeviceConnectionState = .scanning,
        power: ExternalPowerState = .unknown,
        freshness: DataFreshness = .lost,
        powerConfirmedInCurrentSession: Bool = false,
        scanningFor: TimeInterval = 0,
        hasConnectionError: Bool = false,
        isRescanning: Bool = false
    ) -> FirstConnectionPhase {
        FirstConnectionPresentation.resolve(
            started: started,
            bluetooth: bluetooth,
            selection: selection,
            connection: connection,
            power: power,
            freshness: freshness,
            powerConfirmedInCurrentSession: powerConfirmedInCurrentSession,
            scanningFor: scanningFor,
            hasConnectionError: hasConnectionError,
            isRescanning: isRescanning
        )
    }

    return [
        ("first connection starts with one focused discovery action", {
            try expectEqual(phase(started: false, bluetooth: .unknown), .welcome)
        }),
        ("starting discovery changes the screen before Bluetooth reports state", {
            try expectEqual(phase(bluetooth: .unknown), .startingBluetooth)
        }),
        ("initial discovery reports active scanning", {
            try expectEqual(phase(), .searching(candidateCount: 0))
            try expectEqual(
                phase(selection: .init(selectedID: nil, candidates: choices, mode: .initialDiscovery)),
                .searching(candidateCount: 2)
            )
        }),
        ("multiple candidates become a chooser after discovery", {
            try expectEqual(
                phase(selection: .init(selectedID: nil, candidates: choices, mode: .choosing)),
                .choosing
            )
        }),
        ("finished empty discovery offers recovery", {
            try expectEqual(
                phase(selection: .init(selectedID: nil, candidates: [], mode: .choosing)),
                .empty
            )
        }),
        ("Bluetooth problems remain distinct", {
            try expectEqual(phase(bluetooth: .unauthorized), .bluetoothUnauthorized)
            try expectEqual(phase(bluetooth: .poweredOff), .bluetoothOff)
            try expectEqual(phase(bluetooth: .unsupported), .bluetoothUnsupported)
            try expectEqual(phase(bluetooth: .resetting), .bluetoothResetting)
        }),
        ("Bluetooth recovery opens the pane that matches the problem", {
            try expectEqual(
                BluetoothSettingsRecovery.destination(for: .unauthorized),
                .privacyPermission
            )
            try expectEqual(
                BluetoothSettingsRecovery.destination(for: .poweredOff),
                .bluetoothControl
            )
            try expectNil(BluetoothSettingsRecovery.destination(for: .unsupported))
        }),
        ("rescan activity supersedes the old empty or chooser result", {
            try expectEqual(
                phase(
                    selection: .init(selectedID: nil, candidates: [], mode: .choosing),
                    isRescanning: true
                ),
                .rescanning
            )
            try expectEqual(
                phase(
                    selection: .init(selectedID: nil, candidates: choices, mode: .choosing),
                    isRescanning: true
                ),
                .rescanning
            )
        }),
        ("a remembered station waits for an explicit first attempt", {
            let selected = StationSelectionSnapshot(
                selectedID: current,
                candidates: [choices[0]],
                mode: .selectedOnly
            )
            try expectEqual(phase(started: false, selection: selected, connection: .disconnected), .readyToConnect)
        }),
        ("selected station connection states explain progress", {
            let selected = StationSelectionSnapshot(
                selectedID: current,
                candidates: [choices[0]],
                mode: .selectedOnly
            )
            try expectEqual(phase(selection: selected, connection: .connecting), .connecting)
            try expectEqual(phase(selection: selected, connection: .connected), .waitingForTelemetry)
            try expectEqual(phase(selection: selected, connection: .scanning), .findingSelectedStation)
            try expectEqual(
                phase(selection: selected, connection: .scanning, scanningFor: 10),
                .selectedStationNotFound
            )
            try expectEqual(
                phase(selection: selected, connection: .disconnected, hasConnectionError: true),
                .connectionFailed
            )
        }),
        ("current confirmed monitoring resolves as ready", {
            let selected = StationSelectionSnapshot(
                selectedID: current,
                candidates: [choices[0]],
                mode: .selectedOnly
            )
            try expectEqual(
                phase(
                    selection: selected,
                    connection: .connected,
                    power: .offline,
                    freshness: .fresh,
                    powerConfirmedInCurrentSession: true
                ),
                .ready
            )
        }),
    ]
}
