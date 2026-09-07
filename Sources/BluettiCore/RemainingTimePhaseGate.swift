import Foundation

public struct RemainingTimePhaseGate: Sendable {
    private struct Sample: Sendable {
        let watts: Int
        let sampledAt: TimeInterval
    }

    private let maxSampleAge: TimeInterval
    private var power: ExternalPowerState = .unknown
    private var phaseStartedAt: TimeInterval?
    private var dcInput: Sample?
    private var acOutput: Sample?
    private var dcOutput: Sample?
    private var acceptedRuntimeAt: TimeInterval?

    public init(maxSampleAge: TimeInterval = 5) {
        self.maxSampleAge = maxSampleAge
    }

    public mutating func beginPowerPhase(
        _ power: ExternalPowerState,
        at now: TimeInterval
    ) {
        self.power = power
        phaseStartedAt = now
        invalidateTelemetry()
    }

    public mutating func observeDCInputPower(_ watts: Int, at now: TimeInterval) {
        dcInput = Sample(watts: watts, sampledAt: now)
    }

    public mutating func observeACOutputPower(_ watts: Int, at now: TimeInterval) {
        acOutput = Sample(watts: watts, sampledAt: now)
    }

    public mutating func observeDCOutputPower(_ watts: Int, at now: TimeInterval) {
        dcOutput = Sample(watts: watts, sampledAt: now)
    }

    public mutating func accept(
        _ reading: RemainingTimeUpdate,
        at now: TimeInterval
    ) -> RemainingTimeUpdate? {
        guard canUseRuntime(at: now) else {
            acceptedRuntimeAt = nil
            return nil
        }
        switch reading {
        case .available:
            acceptedRuntimeAt = now
        case .unavailable:
            acceptedRuntimeAt = nil
        }
        return reading
    }

    public func hasFreshAcceptedRuntime(at now: TimeInterval) -> Bool {
        guard let acceptedRuntimeAt,
              isFresh(acceptedRuntimeAt, phaseStartedAt: phaseStartedAt, now: now)
        else {
            return false
        }
        return canUseRuntime(at: now)
    }

    public mutating func invalidateTelemetry() {
        dcInput = nil
        acOutput = nil
        dcOutput = nil
        acceptedRuntimeAt = nil
    }

    private func canUseRuntime(at now: TimeInterval) -> Bool {
        guard power == .offline,
              let phaseStartedAt,
              let dcInput,
              let acOutput,
              let dcOutput,
              isFresh(dcInput.sampledAt, phaseStartedAt: phaseStartedAt, now: now),
              isFresh(acOutput.sampledAt, phaseStartedAt: phaseStartedAt, now: now),
              isFresh(dcOutput.sampledAt, phaseStartedAt: phaseStartedAt, now: now),
              dcInput.watts == 0,
              acOutput.watts + dcOutput.watts > 1
        else {
            return false
        }
        return true
    }

    private func isFresh(
        _ sampledAt: TimeInterval,
        phaseStartedAt: TimeInterval?,
        now: TimeInterval
    ) -> Bool {
        guard let phaseStartedAt,
              sampledAt >= phaseStartedAt,
              now >= sampledAt
        else {
            return false
        }
        return now - sampledAt <= maxSampleAge
    }
}
