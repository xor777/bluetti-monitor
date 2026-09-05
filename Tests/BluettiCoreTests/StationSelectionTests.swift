import BluettiCore
import Foundation

func stationSelectionTests() -> [TestCase] {
    let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let secondID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    return [
        ("empty initial discovery waits for explicit selection", {
            var policy = StationSelectionPolicy(selectedID: nil)

            try expectNil(policy.finishInitialDiscovery())
            try expectEqual(policy.mode, .choosing)
            try expectEqual(policy.selectedID, nil)
        }),
        ("one initial candidate is selected and persisted after the discovery window", {
            var policy = StationSelectionPolicy(selectedID: nil)
            _ = policy.observe(StationCandidate(id: firstID, advertisedName: "PR100V2-A1"))

            try expectEqual(
                policy.finishInitialDiscovery(),
                .connect(id: firstID, persistSelection: true, resetCurrentDevice: false)
            )
            try expectEqual(policy.selectedID, firstID)
            try expectEqual(policy.mode, .selectedOnly)
        }),
        ("multiple initial candidates never auto-select", {
            var policy = StationSelectionPolicy(selectedID: nil)
            _ = policy.observe(StationCandidate(id: firstID, advertisedName: "PR100V2-A1"))
            _ = policy.observe(StationCandidate(id: secondID, advertisedName: "PR100V2-B2"))

            try expectNil(policy.finishInitialDiscovery())
            try expectEqual(policy.mode, .choosing)
            try expectEqual(policy.selectedID, nil)
        }),
        ("discovery deduplicates UUID while accepting a better advertised identity", {
            var policy = StationSelectionPolicy(selectedID: nil)
            _ = policy.observe(StationCandidate(id: firstID, advertisedName: ""))
            _ = policy.observe(StationCandidate(id: firstID, advertisedName: "PR100V2-A1"))

            try expectEqual(policy.candidates.count, 1)
            try expectEqual(policy.candidates[0].advertisedName, "PR100V2-A1")
            try expectEqual(policy.candidates[0].displayIdentity, "A1")
        }),
        ("remembered selection ignores every other discovered station", {
            var policy = StationSelectionPolicy(selectedID: firstID)

            try expectNil(policy.observe(StationCandidate(id: secondID, advertisedName: "PR100V2-B2")))
            try expectEqual(
                policy.observe(StationCandidate(id: firstID, advertisedName: "PR100V2-A1")),
                .connect(id: firstID, persistSelection: false, resetCurrentDevice: false)
            )
            try expectEqual(policy.selectedID, firstID)
        }),
        ("canceling change selection keeps the remembered station", {
            var policy = StationSelectionPolicy(selectedID: firstID)
            policy.beginChoosing()
            _ = policy.observe(StationCandidate(id: secondID, advertisedName: "PR100V2-B2"))

            try expectEqual(policy.cancelChoosing(), true)
            try expectEqual(policy.mode, .selectedOnly)
            try expectEqual(policy.selectedID, firstID)
        }),
        ("selecting the current station closes chooser without reconnecting", {
            var policy = StationSelectionPolicy(selectedID: firstID)
            policy.beginChoosing()
            _ = policy.observe(StationCandidate(id: firstID, advertisedName: "PR100V2-A1"))

            try expectEqual(policy.select(firstID), .finishSelection)
            try expectEqual(policy.mode, .selectedOnly)
            try expectEqual(policy.selectedID, firstID)
        }),
        ("committing another station requests reset and persistence", {
            var policy = StationSelectionPolicy(selectedID: firstID)
            policy.beginChoosing()
            _ = policy.observe(StationCandidate(id: secondID, advertisedName: "PR100V2-B2"))

            try expectEqual(
                policy.select(secondID),
                .connect(id: secondID, persistSelection: true, resetCurrentDevice: true)
            )
            try expectEqual(policy.selectedID, secondID)
            try expectEqual(policy.mode, .selectedOnly)
        }),
        ("pending chooser cannot replace a remembered station automatically", {
            var policy = StationSelectionPolicy(selectedID: firstID)
            policy.beginChoosing()
            _ = policy.observe(StationCandidate(id: secondID, advertisedName: "PR100V2-B2"))

            try expectNil(policy.finishInitialDiscovery())
            try expectEqual(policy.selectedID, firstID)
            try expectEqual(policy.mode, .choosing)
        }),
        ("rescan retains the current station marker while clearing other candidates", {
            var policy = StationSelectionPolicy(selectedID: firstID)
            policy.beginChoosing()
            let current = StationCandidate(id: firstID, advertisedName: "PR100V2-A1")
            _ = policy.observe(current)
            _ = policy.observe(StationCandidate(id: secondID, advertisedName: "PR100V2-B2"))

            policy.rescan()
            try expectEqual(policy.candidates, [current])
            try expectEqual(policy.selectedID, firstID)
            try expectEqual(policy.mode, .choosing)
        }),
        ("candidate identity falls back to a short UUID", {
            let candidate = StationCandidate(id: firstID, advertisedName: "PR100V2")

            try expectEqual(candidate.displayIdentity, "1111…1111")
        }),
        ("pending cancellation blocks reconnecting the same cached station", {
            try expectEqual(
                StationConnectionGate.canStart(
                    candidateID: firstID,
                    activeID: firstID,
                    activeIsConnectedOrConnecting: false,
                    pendingCancellationID: firstID
                ),
                false
            )
            try expectEqual(
                StationConnectionGate.canStart(
                    candidateID: secondID,
                    activeID: firstID,
                    activeIsConnectedOrConnecting: false,
                    pendingCancellationID: firstID
                ),
                true
            )
        }),
    ]
}
