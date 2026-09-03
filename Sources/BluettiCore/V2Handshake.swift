import CryptoKit
import Foundation

public enum V2HandshakeState: Equatable, Sendable {
    case awaitingNotifications
    case awaitingChallenge
    case awaitingChallengeAcceptance
    case awaitingPeerKey
    case awaitingKeyAcceptance
    case ready
}

public enum V2HandshakeAction: Equatable, Sendable {
    case none
    case write(Data)
    case ready
}

public enum V2HandshakeError: Error, Equatable, Sendable {
    case unexpectedMessage
    case invalidPeerSignature
    case invalidPeerKey
    case keyAcceptanceFailed
}

public struct V2Handshake {
    private static let productionPeerSigningKey = V2Crypto.data(
        hex: "04A73ABF5D2232C8C1C72E68304343C272495E3A8FD6F30EA96DE2F4B3CE60B251EE21AC667CF8A71E18B46B664EAEFFE3C489F24F695B6411DB7E22CCC85A8594"
    )
    private static let productionLocalSigningKey = V2Crypto.data(
        hex: "4F19A16E3E87BDD9BD24D3E5495B88041511943CBC8B969ADE9641D0F56AF337"
    )

    public private(set) var state: V2HandshakeState = .awaitingNotifications
    public private(set) var insecureIV: Data?
    public private(set) var insecureKey: Data?
    public private(set) var secureKey: Data?

    private let trustedPeerSigningPublicKey: Data
    private let localSigningPrivateKey: Data
    private var localAgreementKey: P256.KeyAgreement.PrivateKey?
    private var peerAgreementKey: P256.KeyAgreement.PublicKey?

    public init(
        trustedPeerSigningPublicKey: Data? = nil,
        localSigningPrivateKey: Data? = nil
    ) {
        self.trustedPeerSigningPublicKey = trustedPeerSigningPublicKey ?? Self.productionPeerSigningKey
        self.localSigningPrivateKey = localSigningPrivateKey ?? Self.productionLocalSigningKey
    }

    public mutating func notificationsEnabled() {
        guard state == .awaitingNotifications else { return }
        state = .awaitingChallenge
    }

    public mutating func receive(_ wireData: Data, encrypted: Bool = false) throws -> V2HandshakeAction {
        let plaintext: Data
        if encrypted {
            guard let insecureKey, let insecureIV else { throw V2HandshakeError.unexpectedMessage }
            plaintext = try V2Crypto.decrypt(wireData, key: insecureKey, fixedIV: insecureIV)
        } else {
            plaintext = wireData
        }
        let message = try V2PreKeyMessage.parse(plaintext)

        switch (state, message.type) {
        case (.awaitingChallenge, 1):
            let material = try V2Crypto.challengeMaterial(challenge: message.data)
            insecureIV = material.iv
            insecureKey = material.key
            state = .awaitingChallengeAcceptance
            return .write(material.response)

        case (.awaitingChallengeAcceptance, 3):
            guard message.data.isEmpty || message.data == Data([0]) else {
                throw V2HandshakeError.unexpectedMessage
            }
            state = .awaitingPeerKey
            return .none

        case (.awaitingPeerKey, 4):
            return try acceptPeerKey(message.data)

        case (.awaitingKeyAcceptance, 6):
            guard message.data == Data([0]),
                  let localAgreementKey,
                  let peerAgreementKey
            else {
                throw V2HandshakeError.keyAcceptanceFailed
            }
            let secret = try localAgreementKey.sharedSecretFromKeyAgreement(with: peerAgreementKey)
            secureKey = secret.withUnsafeBytes { Data($0) }
            state = .ready
            return .ready

        default:
            throw V2HandshakeError.unexpectedMessage
        }
    }

    public mutating func reset() {
        state = .awaitingNotifications
        insecureIV = nil
        insecureKey = nil
        secureKey = nil
        localAgreementKey = nil
        peerAgreementKey = nil
    }

    private mutating func acceptPeerKey(_ data: Data) throws -> V2HandshakeAction {
        guard data.count == 128, let insecureIV, let insecureKey else {
            throw V2HandshakeError.invalidPeerKey
        }
        let peerPublicBytes = Data(data.prefix(64))
        let rawSignature = Data(data.suffix(64))

        do {
            let signingKey = try P256.Signing.PublicKey(
                x963Representation: trustedPeerSigningPublicKey
            )
            let signature = try P256.Signing.ECDSASignature(rawRepresentation: rawSignature)
            guard signingKey.isValidSignature(signature, for: peerPublicBytes + insecureIV) else {
                throw V2HandshakeError.invalidPeerSignature
            }
        } catch let error as V2HandshakeError {
            throw error
        } catch {
            throw V2HandshakeError.invalidPeerSignature
        }

        let peerKey: P256.KeyAgreement.PublicKey
        do {
            peerKey = try P256.KeyAgreement.PublicKey(
                x963Representation: Data([0x04]) + peerPublicBytes
            )
        } catch {
            throw V2HandshakeError.invalidPeerKey
        }

        let agreementKey = P256.KeyAgreement.PrivateKey()
        let localPublicBytes = Data(agreementKey.publicKey.x963Representation.dropFirst())
        let signingKey: P256.Signing.PrivateKey
        do {
            signingKey = try P256.Signing.PrivateKey(rawRepresentation: localSigningPrivateKey)
        } catch {
            throw V2HandshakeError.invalidPeerKey
        }
        let signature = try signingKey.signature(for: localPublicBytes + insecureIV).rawRepresentation
        let response = V2PreKeyMessage.make(type: 5, data: localPublicBytes + signature)

        localAgreementKey = agreementKey
        peerAgreementKey = peerKey
        state = .awaitingKeyAcceptance
        return .write(try V2Crypto.encrypt(response, key: insecureKey, fixedIV: insecureIV))
    }
}
