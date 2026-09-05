import BluettiCore
import Foundation

func monitoringPolicyTests() -> [TestCase] {
    [
        ("freshness becomes stale then lost at exact boundaries", {
            let policy = MonitoringTiming()
            try expectEqual(policy.freshness(age: 2.49), .fresh)
            try expectEqual(policy.freshness(age: 2.5), .stale)
            try expectEqual(policy.freshness(age: 4.99), .stale)
            try expectEqual(policy.freshness(age: 5.0), .lost)
        }),
        ("battery freshness is independent from voltage freshness", {
            let timing = BatterySampleTiming(freshFor: 10)
            try expectEqual(
                timing.freshness(sampledAt: 0, now: 9.9, observedInCurrentSession: true),
                .fresh
            )
            try expectEqual(
                timing.freshness(sampledAt: 0, now: 10.1, observedInCurrentSession: true),
                .stale
            )
            try expectEqual(
                timing.freshness(sampledAt: 10.1, now: 10.1, observedInCurrentSession: false),
                .lost
            )
        }),
        ("battery samples from the apparent future are never fresh", {
            let timing = BatterySampleTiming(freshFor: 10)

            try expectEqual(
                timing.freshness(sampledAt: 20, now: 19, observedInCurrentSession: true),
                .stale
            )
        }),
        ("reconnect backoff is bounded", {
            let backoff = ReconnectBackoff()
            try expectEqual((0...7).map(backoff.delay), [1, 2, 5, 10, 30, 30, 30, 30])
        }),
        ("outage start is recorded only for observed online to offline transition", {
            var tracker = OutageTracker()
            tracker.handle(.initial(.offline), at: 10)
            try expectNil(tracker.startedAt)

            tracker.handle(.changed(from: .online, to: .offline), at: 20)
            try expectEqual(tracker.startedAt, 20)

            tracker.handle(.changed(from: .offline, to: .online), at: 30)
            try expectNil(tracker.startedAt)
        }),
        ("outage tracker resets for device changes", {
            var tracker = OutageTracker()
            tracker.handle(.changed(from: .online, to: .offline), at: 20)
            tracker.reset()
            try expectNil(tracker.startedAt)
        }),
    ]
}
