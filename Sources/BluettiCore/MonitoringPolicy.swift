import Foundation

public struct MonitoringTiming: Sendable {
    public let staleAfter: TimeInterval
    public let lostAfter: TimeInterval

    public init(staleAfter: TimeInterval = 2.5, lostAfter: TimeInterval = 5.0) {
        self.staleAfter = staleAfter
        self.lostAfter = lostAfter
    }

    public func freshness(age: TimeInterval) -> DataFreshness {
        if age >= lostAfter { return .lost }
        if age >= staleAfter { return .stale }
        return .fresh
    }
}

public struct ReconnectBackoff: Sendable {
    private let delays: [TimeInterval]

    public init(delays: [TimeInterval] = [1, 2, 5, 10, 30]) {
        self.delays = delays
    }

    public func delay(_ failureIndex: Int) -> TimeInterval {
        guard !delays.isEmpty else { return 0 }
        return delays[min(max(0, failureIndex), delays.count - 1)]
    }
}
