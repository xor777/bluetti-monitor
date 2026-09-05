import Foundation

public enum PowerTransition: Equatable, Sendable {
    case initial(ExternalPowerState)
    case changed(from: ExternalPowerState, to: ExternalPowerState)
}

public struct PowerStateDetector: Sendable {
    public private(set) var confirmedState: ExternalPowerState
    public private(set) var currentSessionConfirmedState: ExternalPowerState?
    private var candidate: ExternalPowerState?
    private var candidateCount = 0

    public init(previousConfirmed: ExternalPowerState = .unknown) {
        confirmedState = previousConfirmed
        currentSessionConfirmedState = previousConfirmed == .unknown ? nil : previousConfirmed
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
            confirmCurrentSession(observed)
            if currentSessionConfirmedState == observed {
                resetCandidate()
            }
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
        currentSessionConfirmedState = observed
        resetCandidate()
        if previous == .unknown {
            return .initial(observed)
        }
        return .changed(from: previous, to: observed)
    }

    public mutating func beginMonitoringSession() {
        currentSessionConfirmedState = nil
        resetCandidate()
    }

    public mutating func reset() {
        confirmedState = .unknown
        currentSessionConfirmedState = nil
        resetCandidate()
    }

    public mutating func resetCandidate() {
        candidate = nil
        candidateCount = 0
    }

    private mutating func confirmCurrentSession(_ observed: ExternalPowerState) {
        guard currentSessionConfirmedState != observed else { return }
        if candidate == observed {
            candidateCount += 1
        } else {
            candidate = observed
            candidateCount = 1
        }
        if candidateCount >= 2 {
            currentSessionConfirmedState = observed
        }
    }
}
