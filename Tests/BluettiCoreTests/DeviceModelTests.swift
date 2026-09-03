import BluettiCore
import Foundation

func deviceModelTests() -> [TestCase] {
    [
        ("snapshot applies independent telemetry patches", {
            var snapshot = DeviceSnapshot()
            snapshot.apply(TelemetryPatch(batteryPercent: 73))
            snapshot.apply(TelemetryPatch(acInputVoltage: 231.8, acInputPower: 96))
            snapshot.apply(TelemetryPatch(acOutputPower: 94))

            try expectEqual(snapshot.batteryPercent, 73)
            try expectEqual(snapshot.acInputVoltage, 231.8)
            try expectEqual(snapshot.acInputPower, 96)
            try expectEqual(snapshot.acOutputPower, 94)
        }),
    ]
}
