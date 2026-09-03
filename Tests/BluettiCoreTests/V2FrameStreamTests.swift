import BluettiCore
import Foundation

func v2FrameStreamTests() -> [TestCase] {
    [
        ("pre-key frame survives every fragmentation boundary", {
            let fixture = Data([0x2A, 0x2A, 0x01, 0x04, 1, 2, 3, 4, 0, 15])
            for split in 1..<fixture.count {
                var stream = V2FrameStream()
                try expectEqual(try stream.append(fixture.prefix(split)), [])
                let frames = try stream.append(fixture.dropFirst(split))
                try expectEqual(frames, [.preKey(fixture)])
            }
        }),
        ("coalesced pre-key frames are both emitted", {
            let first = V2PreKeyMessage.make(type: 3, data: Data())
            let second = V2PreKeyMessage.make(type: 6, data: Data([0]))
            var stream = V2FrameStream()
            try expectEqual(
                try stream.append(first + second),
                [.preKey(first), .preKey(second)]
            )
        }),
        ("dynamic encrypted frame survives every fragmentation boundary", {
            let fixture = Data([0x00, 0x08, 0xA1, 0xB2, 0xC3, 0xD4] + Array(repeating: 0x7A, count: 16))
            for split in 1..<fixture.count {
                var stream = V2FrameStream(encryptedHeader: .dynamicIV)
                try expectEqual(try stream.append(fixture.prefix(split)), [])
                try expectEqual(try stream.append(fixture.dropFirst(split)), [.encrypted(fixture)])
            }
        }),
        ("oversized declared plaintext is rejected and buffer resets", {
            var stream = V2FrameStream(maximumPlaintextLength: 64)
            try expectThrows(V2FrameError.declaredLengthTooLarge(65)) {
                try stream.append(Data([0x00, 0x41]))
            }
            let frame = V2PreKeyMessage.make(type: 3, data: Data())
            try expectEqual(try stream.append(frame), [.preKey(frame)])
        }),
    ]
}
