import Foundation

public enum RequestCoordinatorError: Error, Equatable, Sendable {
    case busy
    case noPendingRequest
    case wrongEpoch
    case timedOut
}

public struct RequestCoordinator: Sendable {
    private struct Pending: Sendable {
        let read: ModbusRead
        let epoch: UInt64
        let deadline: TimeInterval
    }

    private let timeout: TimeInterval
    private var pending: Pending?

    public init(timeout: TimeInterval = 1.5) {
        self.timeout = timeout
    }

    public var isBusy: Bool { pending != nil }
    public var pendingRead: ModbusRead? { pending?.read }

    public mutating func begin(
        _ read: ModbusRead,
        epoch: UInt64,
        now: TimeInterval
    ) throws -> Data {
        guard pending == nil else { throw RequestCoordinatorError.busy }
        pending = Pending(read: read, epoch: epoch, deadline: now + timeout)
        return Modbus.makeReadRequest(read)
    }

    public mutating func receive(
        _ response: Data,
        epoch: UInt64,
        now: TimeInterval
    ) throws -> TelemetryPatch {
        guard let current = pending else { throw RequestCoordinatorError.noPendingRequest }
        guard current.epoch == epoch else { throw RequestCoordinatorError.wrongEpoch }
        guard now < current.deadline else {
            pending = nil
            throw RequestCoordinatorError.timedOut
        }
        pending = nil
        let payload = try Modbus.parseReadResponse(
            response,
            expectedRegisters: current.read.quantity
        )
        return try PR100V2TelemetryDecoder.decode(read: current.read, payload: payload)
    }

    public mutating func expireIfNeeded(now: TimeInterval) -> Bool {
        guard let pending, now >= pending.deadline else { return false }
        self.pending = nil
        return true
    }

    public mutating func reset() {
        pending = nil
    }
}
