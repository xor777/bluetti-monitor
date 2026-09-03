import BluettiCore
import Foundation

func telemetryDecoderTests() -> [TestCase] {
    [
        ("SOC register decodes percent", {
            let patch = try PR100V2TelemetryDecoder.decode(
                read: .init(startAddress: 102, quantity: 1),
                payload: Data([0x00, 0x64])
            )
            try expectEqual(patch.batteryPercent, 100)
        }),
        ("AC input voltage decodes tenths of a volt", {
            let patch = try PR100V2TelemetryDecoder.decode(
                read: .init(startAddress: 1314, quantity: 1),
                payload: Data([0x09, 0x10])
            )
            try expectEqual(patch.acInputVoltage, 232.0)
        }),
        ("AC input and output power decode watts", {
            let input = try PR100V2TelemetryDecoder.decode(
                read: .init(startAddress: 146, quantity: 1),
                payload: Data([0x00, 0x60])
            )
            let output = try PR100V2TelemetryDecoder.decode(
                read: .init(startAddress: 142, quantity: 1),
                payload: Data([0x00, 0x5E])
            )
            try expectEqual(input.acInputPower, 96)
            try expectEqual(output.acOutputPower, 94)
        }),
        ("model register swaps each byte pair and trims NUL", {
            let patch = try PR100V2TelemetryDecoder.decode(
                read: .init(startAddress: 110, quantity: 6),
                payload: Data([0x52, 0x50, 0x30, 0x31, 0x56, 0x30, 0x00, 0x32, 0, 0, 0, 0])
            )
            try expectEqual(patch.model, "PR100V2")
        }),
        ("payload length mismatch is rejected", {
            try expectThrows(TelemetryDecodeError.invalidPayloadLength(expected: 2, actual: 1)) {
                try PR100V2TelemetryDecoder.decode(
                    read: .init(startAddress: 102, quantity: 1),
                    payload: Data([0x64])
                )
            }
        }),
    ]
}
