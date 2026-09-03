import BluettiCore
import Foundation

func powerStateDetectorTests() -> [TestCase] {
    [
        ("power loss needs two low samples", {
            var detector = PowerStateDetector(previousConfirmed: .online)
            try expectNil(detector.observe(voltage: 0))
            try expectEqual(
                detector.observe(voltage: 0),
                .changed(from: .online, to: .offline)
            )
        }),
        ("restoration needs two high samples", {
            var detector = PowerStateDetector(previousConfirmed: .offline)
            try expectNil(detector.observe(voltage: 232))
            try expectEqual(
                detector.observe(voltage: 232),
                .changed(from: .offline, to: .online)
            )
        }),
        ("uncertain voltage resets candidate", {
            var detector = PowerStateDetector(previousConfirmed: .online)
            try expectNil(detector.observe(voltage: 0))
            try expectNil(detector.observe(voltage: 72))
            try expectNil(detector.observe(voltage: 0))
            try expectEqual(detector.confirmedState, .online)
        }),
        ("first offline state is confirmed after two samples", {
            var detector = PowerStateDetector()
            try expectNil(detector.observe(voltage: 0))
            try expectEqual(detector.observe(voltage: 0), .initial(.offline))
        }),
        ("confirmed state does not emit duplicates", {
            var detector = PowerStateDetector(previousConfirmed: .offline)
            try expectNil(detector.observe(voltage: 0))
            try expectNil(detector.observe(voltage: 0))
            try expectNil(detector.observe(voltage: 0))
        }),
        ("monitoring gap clears only candidates", {
            var detector = PowerStateDetector(previousConfirmed: .online)
            try expectNil(detector.observe(voltage: 0))
            detector.resetCandidate()
            try expectNil(detector.observe(voltage: 0))
            try expectEqual(detector.confirmedState, .online)
        }),
    ]
}
