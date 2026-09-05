import Foundation

public struct StationCandidate: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var advertisedName: String

    public init(id: UUID, advertisedName: String) {
        self.id = id
        self.advertisedName = advertisedName
    }

    public var displayIdentity: String {
        let modelPrefix = "PR100V2"
        if advertisedName.uppercased().hasPrefix(modelPrefix),
           advertisedName.count >= modelPrefix.count
        {
            let suffixStart = advertisedName.index(
                advertisedName.startIndex,
                offsetBy: modelPrefix.count
            )
            let suffix = advertisedName[suffixStart...].trimmingCharacters(
                in: CharacterSet(charactersIn: " -_:")
            )
            if !suffix.isEmpty { return suffix }
        }

        let raw = id.uuidString
        return "\(raw.prefix(4))…\(raw.suffix(4))"
    }
}

public enum StationSelectionMode: Equatable, Sendable {
    case initialDiscovery
    case selectedOnly
    case choosing
}

public enum StationSelectionAction: Equatable, Sendable {
    case connect(
        id: UUID,
        persistSelection: Bool,
        resetCurrentDevice: Bool
    )
    case finishSelection
}

public struct StationSelectionSnapshot: Equatable, Sendable {
    public let selectedID: UUID?
    public let candidates: [StationCandidate]
    public let mode: StationSelectionMode

    public init(
        selectedID: UUID?,
        candidates: [StationCandidate],
        mode: StationSelectionMode
    ) {
        self.selectedID = selectedID
        self.candidates = candidates
        self.mode = mode
    }

    public var isChoosing: Bool { mode == .choosing }
}

public struct StationSelectionPolicy: Sendable {
    public private(set) var selectedID: UUID?
    public private(set) var candidates: [StationCandidate] = []
    public private(set) var mode: StationSelectionMode

    public init(selectedID: UUID?) {
        self.selectedID = selectedID
        mode = selectedID == nil ? .initialDiscovery : .selectedOnly
    }

    public var snapshot: StationSelectionSnapshot {
        StationSelectionSnapshot(
            selectedID: selectedID,
            candidates: candidates,
            mode: mode
        )
    }

    @discardableResult
    public mutating func observe(_ candidate: StationCandidate) -> StationSelectionAction? {
        if let index = candidates.firstIndex(where: { $0.id == candidate.id }) {
            if !candidate.advertisedName.isEmpty {
                candidates[index].advertisedName = candidate.advertisedName
            }
        } else {
            candidates.append(candidate)
        }

        guard mode == .selectedOnly, selectedID == candidate.id else { return nil }
        return .connect(
            id: candidate.id,
            persistSelection: false,
            resetCurrentDevice: false
        )
    }

    public mutating func finishInitialDiscovery() -> StationSelectionAction? {
        guard mode == .initialDiscovery else { return nil }
        guard candidates.count == 1, let candidate = candidates.first else {
            mode = .choosing
            return nil
        }

        selectedID = candidate.id
        mode = .selectedOnly
        return .connect(
            id: candidate.id,
            persistSelection: true,
            resetCurrentDevice: false
        )
    }

    public mutating func beginChoosing() {
        mode = .choosing
    }

    @discardableResult
    public mutating func cancelChoosing() -> Bool {
        guard mode == .choosing, selectedID != nil else { return false }
        mode = .selectedOnly
        return true
    }

    public mutating func rescan() {
        guard mode == .choosing else { return }
        if let selectedID,
           let current = candidates.first(where: { $0.id == selectedID })
        {
            candidates = [current]
        } else {
            candidates.removeAll(keepingCapacity: true)
        }
    }

    public mutating func select(_ id: UUID) -> StationSelectionAction? {
        guard mode == .choosing,
              candidates.contains(where: { $0.id == id })
        else {
            return nil
        }

        if selectedID == id {
            mode = .selectedOnly
            return .finishSelection
        }

        let resetsCurrentDevice = selectedID != nil
        selectedID = id
        mode = .selectedOnly
        return .connect(
            id: id,
            persistSelection: true,
            resetCurrentDevice: resetsCurrentDevice
        )
    }
}

public enum StationConnectionGate {
    public static func canStart(
        candidateID: UUID,
        activeID: UUID?,
        activeIsConnectedOrConnecting: Bool,
        pendingCancellationID: UUID?
    ) -> Bool {
        if pendingCancellationID == candidateID { return false }
        if activeID == candidateID, activeIsConnectedOrConnecting { return false }
        return true
    }
}
