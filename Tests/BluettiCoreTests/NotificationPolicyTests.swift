import BluettiCore
import Foundation

func notificationPolicyTests() -> [TestCase] {
    [
        ("startup offline uses concise absent copy", {
            var policy = NotificationPolicy()
            try expectEqual(policy.handle(.initial(.offline)), .powerAbsent)
            try expectEqual(NotificationEvent.powerAbsent.text, "Питание отсутствует")
        }),
        ("online to offline uses concise loss copy", {
            var policy = NotificationPolicy()
            try expectEqual(policy.handle(.changed(from: .online, to: .offline)), .powerLost)
            try expectEqual(NotificationEvent.powerLost.text, "Питание пропало")
        }),
        ("offline to online uses concise restored copy", {
            var policy = NotificationPolicy()
            try expectEqual(policy.handle(.changed(from: .offline, to: .online)), .powerRestored)
            try expectEqual(NotificationEvent.powerRestored.text, "Питание восстановлено")
        }),
        ("initial online state stays quiet", {
            var policy = NotificationPolicy()
            try expectNil(policy.handle(.initial(.online)))
        }),
        ("connection loss requires a previous ready session and deduplicates", {
            var policy = NotificationPolicy()
            try expectNil(policy.monitoringLost())
            try expectNil(policy.monitoringReady())
            try expectEqual(policy.monitoringLost(), .connectionLost)
            try expectNil(policy.monitoringLost())
            try expectEqual(NotificationEvent.connectionLost.text, "Связь с устройством потеряна")
        }),
        ("reconnection notification follows a notified loss", {
            var policy = NotificationPolicy()
            _ = policy.monitoringReady()
            _ = policy.monitoringLost()
            try expectEqual(policy.monitoringReady(), .connectionRestored)
            try expectNil(policy.monitoringReady())
            try expectEqual(NotificationEvent.connectionRestored.text, "Связь восстановлена")
        }),
        ("test notification copy stays concise", {
            try expectEqual(NotificationEvent.test.text, "Уведомления работают")
        }),
    ]
}
