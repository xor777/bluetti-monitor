import BluettiCore

func menuBarPresentationTests() -> [TestCase] {
    [
        ("online menu bar stays inside one icon slot", {
            let status = MenuBarPresentation.make(.init(
                bluetooth: .poweredOn,
                connection: .connected,
                power: .online,
                freshness: .fresh
            ))
            try expectEqual(status.title, "")
            try expectEqual(status.icon, .online)
        }),
        ("backup menu bar stays inside one icon slot", {
            let status = MenuBarPresentation.make(.init(
                bluetooth: .poweredOn,
                connection: .connected,
                power: .offline,
                freshness: .fresh
            ))
            try expectEqual(status.title, "")
            try expectEqual(status.icon, .backup)
        }),
        ("lost connection is concise", {
            let status = MenuBarPresentation.make(.init(
                bluetooth: .poweredOn,
                connection: .disconnected,
                freshness: .lost
            ))
            try expectEqual(status.title, "")
            try expectEqual(status.icon, .unavailable)
        }),
        ("stale telemetry does not show an old charge", {
            let status = MenuBarPresentation.make(.init(
                bluetooth: .poweredOn,
                connection: .connected,
                power: .online,
                freshness: .stale
            ))
            try expectEqual(status.title, "")
            try expectEqual(status.icon, .stale)
        }),
        ("Bluetooth off is immediately understandable", {
            let status = MenuBarPresentation.make(.init(bluetooth: .poweredOff))
            try expectEqual(status.title, "")
            try expectEqual(status.icon, .unavailable)
        }),
        ("initial connection uses a neutral searching state", {
            let status = MenuBarPresentation.make(.init(
                bluetooth: .poweredOn,
                connection: .connecting
            ))
            try expectEqual(status.title, "")
            try expectEqual(status.icon, .searching)
        }),
    ]
}
