import Foundation

public enum PowerTransition: Equatable, Sendable {
    case initial(ExternalPowerState)
    case changed(from: ExternalPowerState, to: ExternalPowerState)
}

public struct PowerStateDetector: Sendable {
    public private(set) var confirmedState: ExternalPowerState
    private var candidate: ExternalPowerState?
    private var candidateCount = 0

    public init(previousConfirmed: ExternalPowerState = .unknown) {
        confirmedState = previousConfirmed
    }

    public mutating func observe(voltage: Double) -> PowerTransition? {
        let observed: ExternalPowerState?
        if voltage <= 50 {
            observed = .offline
        } else if voltage >= 100 {
            observed = .online
        } else {
            observed = nil
        }

        guard let observed else {
            resetCandidate()
            return nil
        }
        guard observed != confirmedState else {
            resetCandidate()
            return nil
        }

        if candidate == observed {
            candidateCount += 1
        } else {
            candidate = observed
            candidateCount = 1
        }
        guard candidateCount >= 2 else { return nil }

        let previous = confirmedState
        confirmedState = observed
        resetCandidate()
        if previous == .unknown {
            return .initial(observed)
        }
        return .changed(from: previous, to: observed)
    }

    public mutating func resetCandidate() {
        candidate = nil
        candidateCount = 0
    }
}
