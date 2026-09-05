import BluettiCore
import Foundation

func notificationPolicyTests() -> [TestCase] {
    [
        ("startup offline uses concise absent copy", {
            var policy = NotificationPolicy()
            try expectEqual(policy.handle(.initial(.offline)), .powerAbsent(batteryPercent: nil))
            try expectEqual(NotificationEvent.powerAbsent(batteryPercent: nil).russianTitle, "Питание отсутствует")
        }),
        ("online to offline uses concise loss copy", {
            var policy = NotificationPolicy()
            try expectEqual(policy.handle(.changed(from: .online, to: .offline)), .powerLost(batteryPercent: nil))
            try expectEqual(NotificationEvent.powerLost(batteryPercent: nil).russianTitle, "Питание пропало")
        }),
        ("outage copy includes only provided current battery charge", {
            var policy = NotificationPolicy()
            let event = policy.handle(.changed(from: .online, to: .offline), batteryPercent: 19)
            try expectEqual(event, .powerLost(batteryPercent: 19))
            try expectEqual(event?.russianBody, "Заряд станции: 19%")
        }),
        ("offline to online uses concise restored copy", {
            var policy = NotificationPolicy()
            try expectEqual(policy.handle(.changed(from: .offline, to: .online)), .powerRestored)
            try expectEqual(NotificationEvent.powerRestored.russianTitle, "Питание восстановлено")
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
            try expectEqual(NotificationEvent.connectionLost.russianTitle, "Связь с устройством потеряна")
        }),
        ("reconnection notification follows a notified loss", {
            var policy = NotificationPolicy()
            _ = policy.monitoringReady()
            _ = policy.monitoringLost()
            try expectEqual(policy.monitoringReady(), .connectionRestored)
            try expectNil(policy.monitoringReady())
            try expectEqual(NotificationEvent.connectionRestored.russianTitle, "Связь восстановлена")
        }),
        ("device reset clears connection notification episode", {
            var policy = NotificationPolicy()
            _ = policy.monitoringReady()
            _ = policy.monitoringLost()
            policy.resetForDeviceChange()
            try expectNil(policy.monitoringLost())
            try expectNil(policy.monitoringReady())
        }),
        ("test notification copy stays concise", {
            try expectEqual(NotificationEvent.test.russianTitle, "Тест уведомления")
        }),
        ("low battery fires once only for fresh current-session offline state", {
            var policy = LowBatteryAlertPolicy()
            let staleOldSnapshot = LowBatteryAlertInput(
                power: .offline,
                powerConfirmedInCurrentSession: false,
                batteryPercent: 20,
                batteryFreshness: .fresh,
                batteryObservedInCurrentSession: true
            )
            try expectNil(policy.evaluate(staleOldSnapshot))

            let eligible = LowBatteryAlertInput(
                power: .offline,
                powerConfirmedInCurrentSession: true,
                batteryPercent: 20,
                batteryFreshness: .fresh,
                batteryObservedInCurrentSession: true
            )
            try expectEqual(policy.evaluate(eligible), .lowBattery(batteryPercent: 20))
            try expectEqual(
                NotificationEvent.lowBattery(batteryPercent: 20).russianBody,
                "Заряд станции: 20%. Сохраните работу."
            )
            try expectNil(policy.evaluate(eligible))
        }),
        ("low battery does not use stale or invalid charge", {
            var policy = LowBatteryAlertPolicy()
            try expectNil(policy.evaluate(.init(
                power: .offline,
                powerConfirmedInCurrentSession: true,
                batteryPercent: 20,
                batteryFreshness: .stale,
                batteryObservedInCurrentSession: true
            )))
            try expectNil(policy.evaluate(.init(
                power: .offline,
                powerConfirmedInCurrentSession: true,
                batteryPercent: 101,
                batteryFreshness: .fresh,
                batteryObservedInCurrentSession: true
            )))
        }),
        ("low battery re-arms only after restored power or recovered charge", {
            var policy = LowBatteryAlertPolicy()
            let lowOffline = LowBatteryAlertInput(
                power: .offline,
                powerConfirmedInCurrentSession: true,
                batteryPercent: 19,
                batteryFreshness: .fresh,
                batteryObservedInCurrentSession: true
            )
            try expectEqual(policy.evaluate(lowOffline), .lowBattery(batteryPercent: 19))
            try expectNil(policy.evaluate(lowOffline))

            try expectNil(policy.evaluate(.init(
                power: .offline,
                powerConfirmedInCurrentSession: true,
                batteryPercent: 26,
                batteryFreshness: .fresh,
                batteryObservedInCurrentSession: true
            )))
            try expectEqual(policy.evaluate(lowOffline), .lowBattery(batteryPercent: 19))

            try expectNil(policy.evaluate(.init(
                power: .online,
                powerConfirmedInCurrentSession: true,
                batteryPercent: 19,
                batteryFreshness: .fresh,
                batteryObservedInCurrentSession: true
            )))
            try expectEqual(policy.evaluate(lowOffline), .lowBattery(batteryPercent: 19))
        }),
        ("low battery visual state needs valid fresh low charge", {
            try expectEqual(LowBatteryAlertPolicy.visualState(.init(
                power: .offline,
                powerConfirmedInCurrentSession: true,
                batteryPercent: 20,
                batteryFreshness: .fresh,
                batteryObservedInCurrentSession: true
            )), .warning)
            try expectEqual(LowBatteryAlertPolicy.visualState(.init(
                power: .offline,
                powerConfirmedInCurrentSession: true,
                batteryPercent: 20,
                batteryFreshness: .lost,
                batteryObservedInCurrentSession: true
            )), .unavailable)
        }),
        ("notification readiness distinguishes request, blocked and available states", {
            let request = NotificationReadinessPresentation.make(.notDetermined, localizer: russianLocalizer)
            try expectEqual(request.action, .requestAuthorization)
            try expectEqual(request.canScheduleMonitoringAlerts, false)

            let denied = NotificationReadinessPresentation.make(.denied, localizer: russianLocalizer)
            try expectEqual(denied.action, .openSystemSettings)
            try expectEqual(denied.canScheduleMonitoringAlerts, false)

            let alertsDisabled = NotificationReadinessPresentation.make(.alertsDisabled, localizer: russianLocalizer)
            try expectEqual(alertsDisabled.action, .openSystemSettings)
            try expectEqual(alertsDisabled.detail, "Включите баннеры в настройках macOS")

            let available = NotificationReadinessPresentation.make(.available, localizer: russianLocalizer)
            try expectEqual(available.canScheduleMonitoringAlerts, true)
            try expectEqual(available.detail, "macOS может показать баннеры")
        }),
    ]
}

private let russianLocalizer = AppLocalizer(language: .language("ru"))

private extension NotificationEvent {
    var russianTitle: String { content(using: russianLocalizer).title }
    var russianBody: String? { content(using: russianLocalizer).body }
}
