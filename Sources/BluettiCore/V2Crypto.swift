import CommonCrypto
import CryptoKit
import Foundation

public enum V2CryptoError: Error, Equatable, Sendable {
    case invalidChallenge
    case invalidKeyLength
    case invalidIVLength
    case invalidEnvelope
    case plaintextTooLarge
    case cryptorFailure(Int32)
}

public struct V2ChallengeMaterial: Equatable, Sendable {
    public let iv: Data
    public let key: Data
    public let response: Data
}

public enum V2Crypto {
    private static let localAESKey = data(hex: "459FC535808941F17091E0993EE3E93D")

    public static func challengeMaterial(challenge: Data) throws -> V2ChallengeMaterial {
        guard challenge.count == 4 else { throw V2CryptoError.invalidChallenge }
        let iv = Data(Insecure.MD5.hash(data: Data(challenge.reversed())))
        let key = Data(zip(iv, localAESKey).map(^))
        let response = V2PreKeyMessage.make(type: 2, data: iv.subdata(in: 8..<12))
        return V2ChallengeMaterial(iv: iv, key: key, response: response)
    }

    public static func encrypt(
        _ plaintext: Data,
        key: Data,
        fixedIV: Data? = nil,
        seed suppliedSeed: Data? = nil
    ) throws -> Data {
        guard plaintext.count <= Int(UInt16.max) else { throw V2CryptoError.plaintextTooLarge }
        let iv: Data
        var header = Data([
            UInt8(plaintext.count >> 8),
            UInt8(plaintext.count & 0xFF),
        ])

        if let fixedIV {
            iv = fixedIV
        } else {
            let seed = suppliedSeed ?? randomBytes(count: 4)
            guard seed.count == 4 else { throw V2CryptoError.invalidEnvelope }
            header.append(seed)
            iv = Data(Insecure.MD5.hash(data: seed))
        }

        let padding = (16 - plaintext.count % 16) % 16
        let padded = plaintext + Data(repeating: 0, count: padding)
        return header + (try crypt(padded, key: key, iv: iv, operation: CCOperation(kCCEncrypt)))
    }

    public static func decrypt(
        _ envelope: Data,
        key: Data,
        fixedIV: Data? = nil
    ) throws -> Data {
        guard envelope.count >= 2 else { throw V2CryptoError.invalidEnvelope }
        let plaintextLength = (Int(envelope[0]) << 8) | Int(envelope[1])
        let headerLength: Int
        let iv: Data
        if let fixedIV {
            headerLength = 2
            iv = fixedIV
        } else {
            guard envelope.count >= 6 else { throw V2CryptoError.invalidEnvelope }
            headerLength = 6
            iv = Data(Insecure.MD5.hash(data: envelope.subdata(in: 2..<6)))
        }
        let ciphertext = envelope.dropFirst(headerLength)
        guard !ciphertext.isEmpty,
              ciphertext.count.isMultiple(of: 16),
              plaintextLength <= ciphertext.count
        else {
            throw V2CryptoError.invalidEnvelope
        }
        let decrypted = try crypt(
            Data(ciphertext),
            key: key,
            iv: iv,
            operation: CCOperation(kCCDecrypt)
        )
        return decrypted.prefix(plaintextLength)
    }

    private static func crypt(
        _ input: Data,
        key: Data,
        iv: Data,
        operation: CCOperation
    ) throws -> Data {
        guard key.count == kCCKeySizeAES128 || key.count == kCCKeySizeAES192 || key.count == kCCKeySizeAES256 else {
            throw V2CryptoError.invalidKeyLength
        }
        guard iv.count == kCCBlockSizeAES128 else { throw V2CryptoError.invalidIVLength }
        guard input.count.isMultiple(of: kCCBlockSizeAES128) else { throw V2CryptoError.invalidEnvelope }

        var output = Data(repeating: 0, count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(0),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            input.count,
                            outputBytes.baseAddress,
                            outputBytes.count,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw V2CryptoError.cryptorFailure(status) }
        output.removeSubrange(moved..<output.count)
        return output
    }

    private static func randomBytes(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    static func data(hex: String) -> Data {
        var output = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            output.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return output
    }
}
