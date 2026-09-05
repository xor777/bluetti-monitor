import Foundation

public enum FirstRunReadiness {
    public static func isSatisfied(
        selectedID: UUID?,
        connection: DeviceConnectionState,
        power: ExternalPowerState,
        freshness: DataFreshness,
        powerConfirmedInCurrentSession: Bool
    ) -> Bool {
        selectedID != nil
            && connection == .connected
            && power != .unknown
            && freshness == .fresh
            && powerConfirmedInCurrentSession
    }
}
