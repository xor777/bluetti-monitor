import BluettiCore
import Foundation

func modbusTests() -> [TestCase] {
    [
        ("read request uses big-endian fields and little-endian Modbus CRC", {
            let request = Modbus.makeReadRequest(.init(startAddress: 102, quantity: 1))
            try expectEqual(request, Data([0x01, 0x03, 0x00, 0x66, 0x00, 0x01, 0x64, 0x15]))
        }),
        ("valid read response returns register payload", {
            let response = Data([0x01, 0x03, 0x02, 0x00, 0x64, 0xB9, 0xAF])
            let payload = try Modbus.parseReadResponse(response, expectedRegisters: 1)
            try expectEqual(payload, Data([0x00, 0x64]))
        }),
        ("CRC corruption is rejected", {
            let response = Data([0x01, 0x03, 0x02, 0x00, 0x64, 0xB9, 0x00])
            try expectThrows(ModbusError.invalidCRC) {
                try Modbus.parseReadResponse(response, expectedRegisters: 1)
            }
        }),
        ("wrong unit is rejected", {
            let response = Modbus.appendCRC(to: Data([0x02, 0x03, 0x02, 0x00, 0x64]))
            try expectThrows(ModbusError.unexpectedUnit(2)) {
                try Modbus.parseReadResponse(response, expectedRegisters: 1)
            }
        }),
        ("wrong function is rejected", {
            let response = Modbus.appendCRC(to: Data([0x01, 0x04, 0x02, 0x00, 0x64]))
            try expectThrows(ModbusError.unexpectedFunction(4)) {
                try Modbus.parseReadResponse(response, expectedRegisters: 1)
            }
        }),
        ("Modbus exception is surfaced", {
            let response = Data([0x01, 0x83, 0x02, 0xC0, 0xF1])
            try expectThrows(ModbusError.exception(2)) {
                try Modbus.parseReadResponse(response, expectedRegisters: 1)
            }
        }),
        ("wrong byte count is rejected", {
            let response = Modbus.appendCRC(to: Data([0x01, 0x03, 0x04, 0x00, 0x64, 0x00, 0x00]))
            try expectThrows(ModbusError.unexpectedByteCount(expected: 2, actual: 4)) {
                try Modbus.parseReadResponse(response, expectedRegisters: 1)
            }
        }),
        ("trailing response bytes are rejected", {
            let response = Modbus.appendCRC(to: Data([0x01, 0x03, 0x02, 0x00, 0x64, 0x00]))
            try expectThrows(ModbusError.invalidLength) {
                try Modbus.parseReadResponse(response, expectedRegisters: 1)
            }
        }),
    ]
}
