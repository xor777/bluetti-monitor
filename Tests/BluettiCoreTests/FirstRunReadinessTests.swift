import BluettiCore
import Foundation

func firstRunReadinessTests() -> [TestCase] {
    let selectedID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    func isReady(
        selectedID: UUID? = selectedID,
        connection: DeviceConnectionState = .connected,
        power: ExternalPowerState = .online,
        freshness: DataFreshness = .fresh,
        powerConfirmedInCurrentSession: Bool = true
    ) -> Bool {
        FirstRunReadiness.isSatisfied(
            selectedID: selectedID,
            connection: connection,
            power: power,
            freshness: freshness,
            powerConfirmedInCurrentSession: powerConfirmedInCurrentSession
        )
    }

    return [
        ("first run becomes ready only with a selected station and current confirmed monitoring", {
            try expectEqual(isReady(), true)
        }),
        ("selecting a station does not complete first run", {
            try expectEqual(
                isReady(
                    connection: .connecting,
                    power: .unknown,
                    freshness: .lost,
                    powerConfirmedInCurrentSession: false
                ),
                false
            )
        }),
        ("partial monitoring does not complete first run", {
            try expectEqual(isReady(powerConfirmedInCurrentSession: false), false)
        }),
        ("stale monitoring does not complete first run", {
            try expectEqual(isReady(freshness: .stale), false)
        }),
        ("unknown power does not complete first run", {
            try expectEqual(isReady(power: .unknown), false)
        }),
        ("monitoring without a selected station does not complete first run", {
            try expectEqual(isReady(selectedID: nil), false)
        }),
    ]
}
