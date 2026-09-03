import Foundation

public struct StatusContext: Equatable, Sendable {
    public var bluetooth: BluetoothAvailability
    public var connection: DeviceConnectionState
    public var power: ExternalPowerState
    public var freshness: DataFreshness
    public var scanningFor: TimeInterval
    public var inputPower: Int?
    public var outputPower: Int?

    public init(
        bluetooth: BluetoothAvailability = .unknown,
        connection: DeviceConnectionState = .disconnected,
        power: ExternalPowerState = .unknown,
        freshness: DataFreshness = .lost,
        scanningFor: TimeInterval = 0,
        inputPower: Int? = nil,
        outputPower: Int? = nil
    ) {
        self.bluetooth = bluetooth
        self.connection = connection
        self.power = power
        self.freshness = freshness
        self.scanningFor = scanningFor
        self.inputPower = inputPower
        self.outputPower = outputPower
    }
}

public enum StatusTone: Equatable, Sendable {
    case neutral
    case good
    case warning
    case unavailable
}

public struct StatusPresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let tone: StatusTone
    public let inputFlowActive: Bool
    public let outputFlowActive: Bool

    public static func make(_ context: StatusContext) -> StatusPresentation {
        switch context.bluetooth {
        case .poweredOff:
            return inactive("Bluetooth выключен", "Мониторинг остановлен", .unavailable)
        case .unauthorized:
            return inactive("Нет доступа к Bluetooth", "Разрешите доступ в настройках", .unavailable)
        case .unsupported:
            return inactive("Bluetooth недоступен", "Этот Mac не поддерживается", .unavailable)
        case .resetting:
            return inactive("Bluetooth перезапускается", "Подождите", .neutral)
        case .unknown:
            return inactive("Подготовка", "Проверяем Bluetooth", .neutral)
        case .poweredOn:
            break
        }

        switch context.connection {
        case .scanning:
            if context.scanningFor >= 10 {
                return inactive("Устройство не найдено", "Поиск продолжается", .unavailable)
            }
            return inactive("Поиск устройства", "Ищем Premium 100 V2", .neutral)
        case .connecting:
            return inactive("Подключение", "Устанавливаем защищённую связь", .neutral)
        case .disconnected:
            return inactive("Нет связи", "Переподключаемся", .unavailable)
        case .connected:
            break
        }

        if context.freshness == .stale {
            return inactive("Данные устарели", "Обновляем", .warning)
        }
        if context.freshness == .lost {
            return inactive("Нет связи", "Переподключаемся", .unavailable)
        }

        switch context.power {
        case .online:
            return StatusPresentation(
                title: "Сеть подключена",
                subtitle: "Всё работает",
                tone: .good,
                inputFlowActive: (context.inputPower ?? 0) > 1,
                outputFlowActive: (context.outputPower ?? 0) > 1
            )
        case .offline:
            let underLoad = (context.outputPower ?? 0) > 1
            return StatusPresentation(
                title: underLoad ? "Резервное питание" : "Сеть отключена",
                subtitle: underLoad ? "Работа от батареи" : "Внешнее питание отсутствует",
                tone: .warning,
                inputFlowActive: false,
                outputFlowActive: underLoad
            )
        case .unknown:
            return inactive("Получение данных", "Проверяем питание", .neutral)
        }
    }

    private static func inactive(
        _ title: String,
        _ subtitle: String,
        _ tone: StatusTone
    ) -> StatusPresentation {
        StatusPresentation(
            title: title,
            subtitle: subtitle,
            tone: tone,
            inputFlowActive: false,
            outputFlowActive: false
        )
    }
}
