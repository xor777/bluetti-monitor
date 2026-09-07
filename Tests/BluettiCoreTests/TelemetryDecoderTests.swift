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
        ("DC input and output registers keep their distinct addresses", {
            let output = try PR100V2TelemetryDecoder.decode(
                read: .init(startAddress: 140, quantity: 1),
                payload: Data([0x00, 0x07])
            )
            let input = try PR100V2TelemetryDecoder.decode(
                read: .init(startAddress: 144, quantity: 1),
                payload: Data([0x00, 0x1E])
            )
            try expectEqual(output.dcOutputPower, 7)
            try expectEqual(input.dcInputPower, 30)
        }),
        ("remaining time register decodes device minutes", {
            let patch = try PR100V2TelemetryDecoder.decode(
                read: .init(startAddress: 104, quantity: 1),
                payload: Data([0x02, 0x9A])
            )
            try expectEqual(
                patch.remainingTime,
                .available(minutes: 666, isCapped: false)
            )
        }),
        ("99.9 hour device maximum is marked as capped", {
            let patch = try PR100V2TelemetryDecoder.decode(
                read: .init(startAddress: 104, quantity: 1),
                payload: Data([0x17, 0x6A])
            )
            try expectEqual(
                patch.remainingTime,
                .available(minutes: 5994, isCapped: true)
            )
        }),
        ("remaining time sentinels and out-of-range values are unavailable", {
            for (payload, raw) in [
                (Data([0x00, 0x00]), 0),
                (Data([0x17, 0x70]), 6000),
                (Data([0xFF, 0xFF]), 65_535),
            ] {
                let patch = try PR100V2TelemetryDecoder.decode(
                    read: .init(startAddress: 104, quantity: 1),
                    payload: payload
                )
                try expectEqual(patch.remainingTime, .unavailable(raw: raw))
            }
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
