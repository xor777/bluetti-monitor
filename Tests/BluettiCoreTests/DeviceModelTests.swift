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
        ("new monitoring session keeps model identity but clears telemetry", {
            var snapshot = DeviceSnapshot(
                model: "PR100V2",
                batteryPercent: 18,
                acInputVoltage: 230,
                acInputPower: 120,
                acOutputPower: 96,
                dcInputPower: 30,
                dcOutputPower: 7,
                remainingTimeMinutes: 666
            )

            snapshot.clearTelemetryForNewSession()

            try expectEqual(snapshot.model, "PR100V2")
            try expectNil(snapshot.batteryPercent)
            try expectNil(snapshot.acInputVoltage)
            try expectNil(snapshot.acInputPower)
            try expectNil(snapshot.acOutputPower)
            try expectNil(snapshot.dcInputPower)
            try expectNil(snapshot.dcOutputPower)
            try expectNil(snapshot.remainingTimeMinutes)
        }),
        ("remaining time updates set cap metadata and unavailable clears it", {
            var snapshot = DeviceSnapshot()
            snapshot.apply(TelemetryPatch(
                remainingTime: .available(minutes: 5994, isCapped: true)
            ))
            try expectEqual(snapshot.remainingTimeMinutes, 5994)
            try expectEqual(snapshot.remainingTimeIsCapped, true)

            snapshot.apply(TelemetryPatch(remainingTime: .unavailable(raw: 0)))
            try expectNil(snapshot.remainingTimeMinutes)
            try expectEqual(snapshot.remainingTimeIsCapped, false)
        }),
    ]
}
