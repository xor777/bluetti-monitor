import BluettiCore
import Foundation

func statusPresentationTests() -> [TestCase] {
    [
        ("powered off Bluetooth has a specific title", {
            let status = StatusPresentation.make(.init(bluetooth: .poweredOff))
            try expectEqual(status.title, "Bluetooth выключен")
        }),
        ("unauthorized Bluetooth has a specific title", {
            let status = StatusPresentation.make(.init(bluetooth: .unauthorized))
            try expectEqual(status.title, "Нет доступа к Bluetooth")
        }),
        ("scanning becomes not found after ten seconds", {
            let status = StatusPresentation.make(.init(
                bluetooth: .poweredOn,
                connection: .scanning,
                scanningFor: 10
            ))
            try expectEqual(status.title, "Устройство не найдено")
        }),
        ("online state does not overclaim beyond grid connection", {
            let status = StatusPresentation.make(.init(
                bluetooth: .poweredOn,
                connection: .connected,
                power: .online,
                freshness: .fresh,
                outputPower: 94
            ))
            try expectEqual(status.title, "Сеть подключена")
            try expectEqual(status.subtitle, "Всё работает")
        }),
        ("offline under load is backup power", {
            let status = StatusPresentation.make(.init(
                bluetooth: .poweredOn,
                connection: .connected,
                power: .offline,
                freshness: .fresh,
                outputPower: 94
            ))
            try expectEqual(status.title, "Резервное питание")
            try expectEqual(status.inputFlowActive, false)
            try expectEqual(status.outputFlowActive, true)
        }),
        ("offline without load is disconnected grid", {
            let status = StatusPresentation.make(.init(
                bluetooth: .poweredOn,
                connection: .connected,
                power: .offline,
                freshness: .fresh,
                outputPower: 0
            ))
            try expectEqual(status.title, "Сеть отключена")
            try expectEqual(status.outputFlowActive, false)
        }),
        ("stale telemetry overrides prior power state", {
            let status = StatusPresentation.make(.init(
                bluetooth: .poweredOn,
                connection: .connected,
                power: .online,
                freshness: .stale,
                outputPower: 94
            ))
            try expectEqual(status.title, "Данные устарели")
            try expectEqual(status.inputFlowActive, false)
            try expectEqual(status.outputFlowActive, false)
        }),
        ("disconnected telemetry cannot animate", {
            let status = StatusPresentation.make(.init(
                bluetooth: .poweredOn,
                connection: .disconnected,
                power: .online,
                freshness: .lost,
                inputPower: 96,
                outputPower: 94
            ))
            try expectEqual(status.title, "Нет связи")
            try expectEqual(status.inputFlowActive, false)
            try expectEqual(status.outputFlowActive, false)
        }),
    ]
}
