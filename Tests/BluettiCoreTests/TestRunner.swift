import Foundation

@main
enum TestRunner {
    static func main() {
        let tests = deviceModelTests()
            + stationSelectionTests()
            + modbusTests()
            + telemetryDecoderTests()
            + powerStateDetectorTests()
            + monitoringPolicyTests()
            + notificationPolicyTests()
            + v2CryptoTests()
            + v2FrameStreamTests()
            + v2HandshakeTests()
            + requestCoordinatorTests()
            + statusPresentationTests()
            + menuBarPresentationTests()

        var failures = 0
        for test in tests {
            do {
                try test.body()
                print("PASS \(test.name)")
            } catch {
                failures += 1
                print("FAIL \(test.name): \(error)")
            }
        }

        guard failures == 0 else {
            print("\(failures) of \(tests.count) tests failed")
            exit(1)
        }
        print("\(tests.count) tests passed")
    }
}
