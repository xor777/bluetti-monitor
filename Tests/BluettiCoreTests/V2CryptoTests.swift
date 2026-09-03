import BluettiCore
import Foundation

func v2CryptoTests() -> [TestCase] {
    [
        ("challenge derives the verified IV key and response", {
            let material = try V2Crypto.challengeMaterial(challenge: Data([1, 2, 3, 4]))
            try expectEqual(material.iv.hex, "c73cabeb6558aba030bba9ca49dcdd75")
            try expectEqual(material.key.hex, "82a36edee5d1ea51402a4953773f3448")
            try expectEqual(material.response.hex, "2a2a020430bba9ca0264")
        }),
        ("fixed-IV AES envelope matches reference fixture and decrypts", {
            let material = try V2Crypto.challengeMaterial(challenge: Data([1, 2, 3, 4]))
            let plaintext = Data([0x01, 0x03, 0x00, 0x66, 0x00, 0x01, 0x64, 0x15])
            let envelope = try V2Crypto.encrypt(
                plaintext,
                key: material.key,
                fixedIV: material.iv
            )
            try expectEqual(envelope.hex, "000883ada0cdda371dc62784f0bdbac9d51c")
            try expectEqual(
                try V2Crypto.decrypt(envelope, key: material.key, fixedIV: material.iv),
                plaintext
            )
        }),
        ("dynamic-IV AES envelope includes seed and decrypts", {
            let key = try Data(hex: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff")
            let seed = Data([0xA1, 0xB2, 0xC3, 0xD4])
            let plaintext = Data([0x01, 0x03, 0x00, 0x66, 0x00, 0x01, 0x64, 0x15])
            let envelope = try V2Crypto.encrypt(plaintext, key: key, seed: seed)
            try expectEqual(envelope.hex, "0008a1b2c3d4f2c5b09caeda80310fcd914bddba6f64")
            try expectEqual(try V2Crypto.decrypt(envelope, key: key), plaintext)
        }),
        ("unaligned ciphertext is rejected", {
            let key = Data(repeating: 0, count: 32)
            try expectThrows(V2CryptoError.invalidEnvelope) {
                try V2Crypto.decrypt(Data([0, 1, 0, 0, 0, 0, 0]), key: key)
            }
        }),
    ]
}

private extension Data {
    init(hex: String) throws {
        guard hex.count.isMultiple(of: 2) else { throw TestFailure(description: "Odd hex length") }
        self.init()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                throw TestFailure(description: "Invalid hex")
            }
            append(byte)
            index = next
        }
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
