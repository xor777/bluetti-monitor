import BluettiCore

func remainingTimePhaseGateTests() -> [TestCase] {
    let reading = RemainingTimeUpdate.available(minutes: 666, isCapped: false)

    return [
        ("offline runtime waits for current-phase input and output samples", {
            var gate = RemainingTimePhaseGate()
            gate.beginPowerPhase(.offline, at: 10)
            gate.observeDCInputPower(0, at: 10.1)
            gate.observeACOutputPower(104, at: 10.2)

            try expectNil(gate.accept(reading, at: 10.3))

            gate.observeDCOutputPower(0, at: 10.4)
            try expectEqual(gate.accept(reading, at: 10.5), reading)
        }),
        ("online and no-load phases reject backup runtime", {
            var gate = RemainingTimePhaseGate()
            gate.beginPowerPhase(.online, at: 10)
            gate.observeDCInputPower(0, at: 10.1)
            gate.observeACOutputPower(104, at: 10.2)
            gate.observeDCOutputPower(0, at: 10.3)
            try expectNil(gate.accept(reading, at: 10.4))

            gate.beginPowerPhase(.offline, at: 20)
            gate.observeDCInputPower(0, at: 20.1)
            gate.observeACOutputPower(0, at: 20.2)
            gate.observeDCOutputPower(0, at: 20.3)
            try expectNil(gate.accept(reading, at: 20.4))
        }),
        ("DC charging makes offline remaining-time mode ambiguous", {
            var gate = RemainingTimePhaseGate()
            gate.beginPowerPhase(.offline, at: 10)
            gate.observeDCInputPower(30, at: 10.1)
            gate.observeACOutputPower(104, at: 10.2)
            gate.observeDCOutputPower(0, at: 10.3)

            try expectNil(gate.accept(reading, at: 10.4))
        }),
        ("online cap cannot become backup runtime after offline transition", {
            var gate = RemainingTimePhaseGate()
            let onlineCap = RemainingTimeUpdate.available(minutes: 5994, isCapped: true)
            gate.beginPowerPhase(.online, at: 10)
            gate.observeDCInputPower(0, at: 10.1)
            gate.observeACOutputPower(104, at: 10.2)
            gate.observeDCOutputPower(0, at: 10.3)
            try expectNil(gate.accept(onlineCap, at: 10.4))

            gate.beginPowerPhase(.offline, at: 11)
            try expectNil(gate.accept(onlineCap, at: 11.1))
        }),
        ("field ages and telemetry invalidation expire accepted runtime", {
            var gate = RemainingTimePhaseGate(maxSampleAge: 5)
            gate.beginPowerPhase(.offline, at: 10)
            gate.observeDCInputPower(0, at: 10.1)
            gate.observeACOutputPower(104, at: 10.2)
            gate.observeDCOutputPower(0, at: 10.3)
            try expectEqual(gate.accept(reading, at: 10.4), reading)
            try expectEqual(gate.hasFreshAcceptedRuntime(at: 15.09), true)
            try expectEqual(gate.hasFreshAcceptedRuntime(at: 15.11), false)

            gate.invalidateTelemetry()
            try expectEqual(gate.hasFreshAcceptedRuntime(at: 10.5), false)
        }),
    ]
}
