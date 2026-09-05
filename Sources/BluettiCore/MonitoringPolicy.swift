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

public struct BatterySampleTiming: Sendable {
    public let freshFor: TimeInterval

    public init(freshFor: TimeInterval = 10.0) {
        self.freshFor = freshFor
    }

    public func freshness(
        sampledAt: TimeInterval?,
        now: TimeInterval,
        observedInCurrentSession: Bool
    ) -> DataFreshness {
        guard observedInCurrentSession, let sampledAt else { return .lost }
        let age = now - sampledAt
        guard age >= 0 else { return .stale }
        return age <= freshFor ? .fresh : .stale
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

public struct OutageTracker: Sendable {
    public private(set) var startedAt: TimeInterval?

    public init(startedAt: TimeInterval? = nil) {
        self.startedAt = startedAt
    }

    public mutating func handle(_ transition: PowerTransition, at timestamp: TimeInterval) {
        switch transition {
        case .changed(from: .online, to: .offline):
            startedAt = timestamp
        case .changed(from: .offline, to: .online):
            startedAt = nil
        case .initial, .changed:
            break
        }
    }

    public mutating func reset() {
        startedAt = nil
    }
}
