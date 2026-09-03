import Foundation

public struct ModbusRead: Equatable, Hashable, Sendable {
    public let startAddress: UInt16
    public let quantity: UInt16

    public init(startAddress: UInt16, quantity: UInt16) {
        self.startAddress = startAddress
        self.quantity = quantity
    }
}

public enum ModbusError: Error, Equatable, Sendable {
    case invalidLength
    case invalidCRC
    case unexpectedUnit(UInt8)
    case unexpectedFunction(UInt8)
    case exception(UInt8)
    case unexpectedByteCount(expected: Int, actual: Int)
}

public enum Modbus {
    public static func appendCRC(to body: Data) -> Data {
        var framed = body
        let crc = CRC16.modbus(body)
        framed.append(UInt8(crc & 0xFF))
        framed.append(UInt8(crc >> 8))
        return framed
    }

    public static func makeReadRequest(_ read: ModbusRead, unitID: UInt8 = 1) -> Data {
        var body = Data([unitID, 0x03])
        body.append(UInt8(read.startAddress >> 8))
        body.append(UInt8(read.startAddress & 0xFF))
        body.append(UInt8(read.quantity >> 8))
        body.append(UInt8(read.quantity & 0xFF))
        return appendCRC(to: body)
    }

    public static func parseReadResponse(
        _ response: Data,
        expectedRegisters: UInt16,
        unitID: UInt8 = 1
    ) throws -> Data {
        guard response.count >= 5 else { throw ModbusError.invalidLength }

        let suppliedCRC = UInt16(response[response.count - 2])
            | (UInt16(response[response.count - 1]) << 8)
        guard CRC16.modbus(response.dropLast(2)) == suppliedCRC else {
            throw ModbusError.invalidCRC
        }
        guard response[0] == unitID else {
            throw ModbusError.unexpectedUnit(response[0])
        }

        if response[1] == 0x83 {
            guard response.count == 5 else { throw ModbusError.invalidLength }
            throw ModbusError.exception(response[2])
        }
        guard response[1] == 0x03 else {
            throw ModbusError.unexpectedFunction(response[1])
        }

        let actualByteCount = Int(response[2])
        guard response.count == actualByteCount + 5 else {
            throw ModbusError.invalidLength
        }
        let expectedByteCount = Int(expectedRegisters) * 2
        guard actualByteCount == expectedByteCount else {
            throw ModbusError.unexpectedByteCount(
                expected: expectedByteCount,
                actual: actualByteCount
            )
        }
        return response.subdata(in: 3..<(3 + actualByteCount))
    }
}
