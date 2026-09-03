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
        ("reconnect backoff is bounded", {
            let backoff = ReconnectBackoff()
            try expectEqual((0...7).map(backoff.delay), [1, 2, 5, 10, 30, 30, 30, 30])
        }),
    ]
}
