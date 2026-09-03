import BluettiCore
import CryptoKit
import Foundation

func v2HandshakeTests() -> [TestCase] {
    [
        ("notifications must be enabled before challenge", {
            var handshake = V2Handshake()
            let challenge = V2PreKeyMessage.make(type: 1, data: Data([1, 2, 3, 4]))
            try expectThrows(V2HandshakeError.unexpectedMessage) {
                try handshake.receive(challenge)
            }
        }),
        ("challenge and acceptance advance in order", {
            var handshake = V2Handshake()
            handshake.notificationsEnabled()
            let challenge = V2PreKeyMessage.make(type: 1, data: Data([1, 2, 3, 4]))
            try expectEqual(
                try handshake.receive(challenge),
                .write(Data([0x2A, 0x2A, 0x02, 0x04, 0x30, 0xBB, 0xA9, 0xCA, 0x02, 0x64]))
            )
            try expectEqual(handshake.state, .awaitingChallengeAcceptance)
            let accepted = V2PreKeyMessage.make(type: 3, data: Data([0]))
            try expectEqual(try handshake.receive(accepted), .none)
            try expectEqual(handshake.state, .awaitingPeerKey)
        }),
        ("signed peer exchange produces a mutually derived secure key", {
            let trustedSigner = P256.Signing.PrivateKey()
            let localSigner = P256.Signing.PrivateKey()
            var handshake = V2Handshake(
                trustedPeerSigningPublicKey: trustedSigner.publicKey.x963Representation,
                localSigningPrivateKey: localSigner.rawRepresentation
            )
            handshake.notificationsEnabled()
            _ = try handshake.receive(V2PreKeyMessage.make(type: 1, data: Data([1, 2, 3, 4])))
            _ = try handshake.receive(V2PreKeyMessage.make(type: 3, data: Data([0])))

            let peerAgreement = P256.KeyAgreement.PrivateKey()
            let peerPublic = peerAgreement.publicKey.x963Representation.dropFirst()
            let signed = Data(peerPublic) + (handshake.insecureIV ?? Data())
            let signature = try trustedSigner.signature(for: signed).rawRepresentation
            let peerMessage = V2PreKeyMessage.make(
                type: 4,
                data: Data(peerPublic) + signature
            )
            let peerEnvelope = try V2Crypto.encrypt(
                peerMessage,
                key: handshake.insecureKey ?? Data(),
                fixedIV: handshake.insecureIV ?? Data()
            )
            let response = try handshake.receive(peerEnvelope, encrypted: true)
            guard case let .write(responseEnvelope) = response else {
                throw TestFailure(description: "Expected encrypted local key response")
            }
            let responsePlaintext = try V2Crypto.decrypt(
                responseEnvelope,
                key: handshake.insecureKey ?? Data(),
                fixedIV: handshake.insecureIV
            )
            let localMessage = try V2PreKeyMessage.parse(responsePlaintext)
            try expectEqual(localMessage.type, 5)
            try expectEqual(localMessage.data.count, 128)
            let localPublic = Data([0x04]) + localMessage.data.prefix(64)
            let localSignature = try P256.Signing.ECDSASignature(
                rawRepresentation: localMessage.data.suffix(64)
            )
            let localPublicKey = try P256.Signing.PublicKey(x963Representation: localSigner.publicKey.x963Representation)
            try expectEqual(
                localPublicKey.isValidSignature(
                    localSignature,
                    for: Data(localMessage.data.prefix(64)) + (handshake.insecureIV ?? Data())
                ),
                true
            )

            let accepted = V2PreKeyMessage.make(type: 6, data: Data([0]))
            let acceptedEnvelope = try V2Crypto.encrypt(
                accepted,
                key: handshake.insecureKey ?? Data(),
                fixedIV: handshake.insecureIV
            )
            try expectEqual(try handshake.receive(acceptedEnvelope, encrypted: true), .ready)
            let peerViewOfSecret = try peerAgreement.sharedSecretFromKeyAgreement(
                with: try P256.KeyAgreement.PublicKey(x963Representation: localPublic)
            )
            try expectEqual(handshake.secureKey, peerViewOfSecret.withUnsafeBytes { Data($0) })
            try expectEqual(handshake.state, .ready)
        }),
        ("peer key with an invalid signature is rejected", {
            let trustedSigner = P256.Signing.PrivateKey()
            var handshake = V2Handshake(
                trustedPeerSigningPublicKey: trustedSigner.publicKey.x963Representation
            )
            handshake.notificationsEnabled()
            _ = try handshake.receive(V2PreKeyMessage.make(type: 1, data: Data([1, 2, 3, 4])))
            _ = try handshake.receive(V2PreKeyMessage.make(type: 3, data: Data([0])))
            let peer = P256.KeyAgreement.PrivateKey().publicKey.x963Representation.dropFirst()
            let message = V2PreKeyMessage.make(type: 4, data: Data(peer) + Data(repeating: 0, count: 64))
            let envelope = try V2Crypto.encrypt(
                message,
                key: handshake.insecureKey ?? Data(),
                fixedIV: handshake.insecureIV
            )
            try expectThrows(V2HandshakeError.invalidPeerSignature) {
                try handshake.receive(envelope, encrypted: true)
            }
        }),
    ]
}
