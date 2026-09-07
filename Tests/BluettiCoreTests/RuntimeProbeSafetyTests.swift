import BluettiCore

func runtimeProbeSafetyTests() -> [TestCase] {
    let candidate = ModbusRead(startAddress: 104, quantity: 1)
    let voltage = ModbusRead(startAddress: 1314, quantity: 1)

    return [
        ("any timeout while probing requires a reconnect barrier", {
            var safety = RuntimeProbeSafety(enabled: true, probeRead: candidate)

            try expectEqual(
                safety.handle(.timedOut, pendingRead: voltage),
                .disableAndReconnect
            )
            try expectEqual(safety.isEnabled, false)
        }),
        ("candidate Modbus exception disables only the optional read", {
            var safety = RuntimeProbeSafety(enabled: true, probeRead: candidate)

            try expectEqual(
                safety.handle(.modbusException(2), pendingRead: candidate),
                .disableAndContinue
            )
            try expectEqual(safety.isEnabled, false)
        }),
        ("normal failures preserve existing handling when probe is off", {
            var safety = RuntimeProbeSafety(enabled: false, probeRead: candidate)

            try expectEqual(
                safety.handle(.timedOut, pendingRead: voltage),
                .propagate
            )
            try expectEqual(safety.isEnabled, false)
        }),
        ("non-probe Modbus exceptions keep normal failure handling", {
            var safety = RuntimeProbeSafety(enabled: true, probeRead: candidate)

            try expectEqual(
                safety.handle(.modbusException(2), pendingRead: voltage),
                .propagate
            )
            try expectEqual(safety.isEnabled, true)
        }),
    ]
}
