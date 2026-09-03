import Foundation

public struct V2PreKeyMessage: Equatable, Sendable {
    public let type: UInt8
    public let data: Data

    public static func make(type: UInt8, data: Data) -> Data {
        precondition(data.count <= 255)
        var body = Data([type, UInt8(data.count)])
        body.append(data)
        let checksum = body.reduce(0) { $0 + UInt16($1) }
        return Data([0x2A, 0x2A])
            + body
            + Data([UInt8(checksum >> 8), UInt8(checksum & 0xFF)])
    }

    public static func parse(_ frame: Data) throws -> V2PreKeyMessage {
        guard frame.count >= 6, frame[0] == 0x2A, frame[1] == 0x2A else {
            throw V2FrameError.invalidPreKeyFrame
        }
        let dataLength = Int(frame[3])
        guard frame.count == dataLength + 6 else { throw V2FrameError.invalidPreKeyFrame }
        let body = frame.subdata(in: 2..<(4 + dataLength))
        let expected = body.reduce(0) { $0 + UInt16($1) }
        let actual = (UInt16(frame[frame.count - 2]) << 8) | UInt16(frame[frame.count - 1])
        guard actual == expected else { throw V2FrameError.invalidChecksum }
        return V2PreKeyMessage(type: frame[2], data: frame.subdata(in: 4..<(4 + dataLength)))
    }
}

public enum V2EncryptedHeader: Equatable, Sendable {
    case fixedIV
    case dynamicIV
}

public enum V2WireFrame: Equatable, Sendable {
    case preKey(Data)
    case encrypted(Data)
}

public enum V2FrameError: Error, Equatable, Sendable {
    case invalidPreKeyFrame
    case invalidChecksum
    case declaredLengthTooLarge(Int)
    case bufferLimitExceeded
}

public struct V2FrameStream: Sendable {
    public var encryptedHeader: V2EncryptedHeader
    private let maximumPlaintextLength: Int
    private let maximumBufferLength: Int
    private var buffer = Data()

    public init(
        encryptedHeader: V2EncryptedHeader = .fixedIV,
        maximumPlaintextLength: Int = 4_096,
        maximumBufferLength: Int = 8_192
    ) {
        self.encryptedHeader = encryptedHeader
        self.maximumPlaintextLength = maximumPlaintextLength
        self.maximumBufferLength = maximumBufferLength
    }

    public mutating func append<D: DataProtocol>(_ bytes: D) throws -> [V2WireFrame] {
        buffer.append(contentsOf: bytes)
        guard buffer.count <= maximumBufferLength else {
            buffer.removeAll(keepingCapacity: true)
            throw V2FrameError.bufferLimitExceeded
        }

        var frames: [V2WireFrame] = []
        do {
            while let frame = try nextFrame() {
                frames.append(frame)
            }
            return frames
        } catch {
            buffer.removeAll(keepingCapacity: true)
            throw error
        }
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    private mutating func nextFrame() throws -> V2WireFrame? {
        guard buffer.count >= 2 else { return nil }
        if buffer[0] == 0x2A && buffer[1] == 0x2A {
            guard buffer.count >= 4 else { return nil }
            let dataLength = Int(buffer[3])
            guard dataLength <= maximumPlaintextLength else {
                throw V2FrameError.declaredLengthTooLarge(dataLength)
            }
            let totalLength = dataLength + 6
            guard buffer.count >= totalLength else { return nil }
            let frame = buffer.prefix(totalLength)
            buffer = Data(buffer.dropFirst(totalLength))
            return .preKey(Data(frame))
        }

        let plaintextLength = (Int(buffer[0]) << 8) | Int(buffer[1])
        guard plaintextLength <= maximumPlaintextLength else {
            throw V2FrameError.declaredLengthTooLarge(plaintextLength)
        }
        let headerLength = encryptedHeader == .fixedIV ? 2 : 6
        guard buffer.count >= headerLength else { return nil }
        let paddedLength = ((plaintextLength + 15) / 16) * 16
        let totalLength = headerLength + paddedLength
        guard buffer.count >= totalLength else { return nil }
        let frame = buffer.prefix(totalLength)
        buffer = Data(buffer.dropFirst(totalLength))
        return .encrypted(Data(frame))
    }
}
