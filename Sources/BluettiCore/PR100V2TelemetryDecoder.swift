import Foundation

public enum TelemetryDecodeError: Error, Equatable, Sendable {
    case invalidPayloadLength(expected: Int, actual: Int)
    case unsupportedRead(ModbusRead)
}

public enum PR100V2TelemetryDecoder {
    public static let model = ModbusRead(startAddress: 110, quantity: 6)
    public static let batteryPercent = ModbusRead(startAddress: 102, quantity: 1)
    public static let remainingTime = ModbusRead(startAddress: 104, quantity: 1)
    public static let dcOutputPower = ModbusRead(startAddress: 140, quantity: 1)
    public static let acOutputPower = ModbusRead(startAddress: 142, quantity: 1)
    public static let dcInputPower = ModbusRead(startAddress: 144, quantity: 1)
    public static let acInputPower = ModbusRead(startAddress: 146, quantity: 1)
    public static let acInputVoltage = ModbusRead(startAddress: 1314, quantity: 1)

    public static func decode(read: ModbusRead, payload: Data) throws -> TelemetryPatch {
        let expectedLength = Int(read.quantity) * 2
        guard payload.count == expectedLength else {
            throw TelemetryDecodeError.invalidPayloadLength(
                expected: expectedLength,
                actual: payload.count
            )
        }

        switch read {
        case model:
            var swapped = Data(capacity: payload.count)
            for index in stride(from: 0, to: payload.count, by: 2) {
                swapped.append(payload[index + 1])
                swapped.append(payload[index])
            }
            let bytes = swapped.prefix { $0 != 0 }
            return TelemetryPatch(model: String(decoding: bytes, as: UTF8.self))
        case batteryPercent:
            return TelemetryPatch(batteryPercent: Int(word(payload)))
        case remainingTime:
            let raw = Int(word(payload))
            guard (1...5994).contains(raw) else {
                return TelemetryPatch(remainingTime: .unavailable(raw: raw))
            }
            return TelemetryPatch(
                remainingTime: .available(minutes: raw, isCapped: raw == 5994)
            )
        case acInputVoltage:
            return TelemetryPatch(acInputVoltage: Double(word(payload)) / 10.0)
        case acInputPower:
            return TelemetryPatch(acInputPower: Int(word(payload)))
        case acOutputPower:
            return TelemetryPatch(acOutputPower: Int(word(payload)))
        case dcInputPower:
            return TelemetryPatch(dcInputPower: Int(word(payload)))
        case dcOutputPower:
            return TelemetryPatch(dcOutputPower: Int(word(payload)))
        default:
            throw TelemetryDecodeError.unsupportedRead(read)
        }
    }

    private static func word(_ data: Data) -> UInt16 {
        (UInt16(data[0]) << 8) | UInt16(data[1])
    }
}
