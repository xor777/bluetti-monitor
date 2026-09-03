@preconcurrency import CoreBluetooth
import AppKit
import BluettiCore
import Foundation
import OSLog

@MainActor
protocol BluetoothCentralEvents: AnyObject {
    func bluetoothAvailabilityChanged(_ availability: BluetoothAvailability)
    func bluetoothConnectionChanged(
        _ state: DeviceConnectionState,
        epoch: UInt64,
        peripheralID: UUID?
    )
    func bluetoothNotificationsEnabled(epoch: UInt64)
    func bluetoothReceived(_ data: Data, epoch: UInt64)
    func bluetoothDisconnected(epoch: UInt64, error: String?, attempt: Int)
}

@MainActor
final class BluetoothCentral: NSObject {
    static let notifyUUID = CBUUID(string: "FF01")
    static let writeUUID = CBUUID(string: "FF02")

    weak var events: BluetoothCentralEvents?

    private lazy var manager = CBCentralManager(delegate: self, queue: .main)
    private let logger = Logger(subsystem: "com.dmitry.bluetti-monitor", category: "Bluetooth")
    private var peripheral: CBPeripheral?
    private var notifyCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?
    private var reconnectGeneration: UInt64 = 0
    private var reconnectAttempt = 0
    private(set) var epoch: UInt64 = 0

    func start() {
        _ = manager
    }

    func write(_ data: Data, epoch expectedEpoch: UInt64) -> Bool {
        guard expectedEpoch == epoch,
              let peripheral,
              peripheral.state == .connected,
              let writeCharacteristic
        else {
            return false
        }
        let writeType: CBCharacteristicWriteType = writeCharacteristic.properties.contains(.write)
            ? .withResponse
            : .withoutResponse
        peripheral.writeValue(data, for: writeCharacteristic, type: writeType)
        return true
    }

    func markMonitoringReady() {
        reconnectAttempt = 0
    }

    func reconnectImmediately() {
        reconnectAttempt = 0
        reconnect(after: 0)
    }

    func reconnectAfterFailure() {
        let delay = ReconnectBackoff().delay(reconnectAttempt)
        reconnectAttempt += 1
        reconnect(after: delay)
    }

    func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") else { return }
        NSWorkspace.shared.open(url)
    }

    private func connect(_ candidate: CBPeripheral) {
        reconnectGeneration &+= 1
        manager.stopScan()
        epoch &+= 1
        peripheral = candidate
        notifyCharacteristic = nil
        writeCharacteristic = nil
        candidate.delegate = self
        UserDefaults.standard.set(candidate.identifier.uuidString, forKey: "lastPeripheralIdentifier")
        events?.bluetoothConnectionChanged(.connecting, epoch: epoch, peripheralID: candidate.identifier)
        logger.info("Connecting to PR100V2, epoch \(self.epoch)")
        manager.connect(candidate, options: nil)
    }

    private func scanOrRestore() {
        guard manager.state == .poweredOn else { return }
        if let rawID = UserDefaults.standard.string(forKey: "lastPeripheralIdentifier"),
           let id = UUID(uuidString: rawID),
           let restored = manager.retrievePeripherals(withIdentifiers: [id]).first
        {
            connect(restored)
            return
        }
        events?.bluetoothConnectionChanged(.scanning, epoch: epoch, peripheralID: nil)
        manager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func reconnect(after delay: TimeInterval) {
        reconnectGeneration &+= 1
        let generation = reconnectGeneration
        if let peripheral {
            peripheral.delegate = nil
            manager.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        notifyCharacteristic = nil
        writeCharacteristic = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  generation == self.reconnectGeneration,
                  self.manager.state == .poweredOn
            else { return }
            self.scanOrRestore()
        }
    }

    private func failCurrent(_ error: Error?) {
        let message = error.map { String(describing: $0) }
        logger.error("Connection ended, attempt \(self.reconnectAttempt + 1): \(message ?? "no detail", privacy: .public)")
        events?.bluetoothDisconnected(
            epoch: epoch,
            error: message,
            attempt: reconnectAttempt + 1
        )
        reconnectAfterFailure()
    }
}

extension BluetoothCentral: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let availability: BluetoothAvailability
        switch central.state {
        case .unknown: availability = .unknown
        case .resetting: availability = .resetting
        case .unsupported: availability = .unsupported
        case .unauthorized: availability = .unauthorized
        case .poweredOff: availability = .poweredOff
        case .poweredOn: availability = .poweredOn
        @unknown default: availability = .unknown
        }
        events?.bluetoothAvailabilityChanged(availability)
        logger.info("Bluetooth state: \(String(describing: availability), privacy: .public)")
        if central.state == .poweredOn {
            scanOrRestore()
        } else {
            manager.stopScan()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover candidate: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertised ?? candidate.name ?? ""
        guard name.uppercased().hasPrefix("PR100V2") else { return }
        logger.info("Found PR100V2 candidate")
        connect(candidate)
    }

    func centralManager(_ central: CBCentralManager, didConnect connected: CBPeripheral) {
        guard connected === peripheral else { return }
        connected.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect failed: CBPeripheral,
        error: Error?
    ) {
        guard failed === peripheral else { return }
        failCurrent(error)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral disconnected: CBPeripheral,
        error: Error?
    ) {
        guard disconnected === peripheral else { return }
        failCurrent(error)
    }
}

extension BluetoothCentral: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral else { return }
        if let error {
            failCurrent(error)
            return
        }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(
                [Self.notifyUUID, Self.writeUUID],
                for: service
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard peripheral === self.peripheral else { return }
        if let error {
            failCurrent(error)
            return
        }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.notifyUUID { notifyCharacteristic = characteristic }
            if characteristic.uuid == Self.writeUUID { writeCharacteristic = characteristic }
        }
        guard let notifyCharacteristic, writeCharacteristic != nil else { return }
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral === self.peripheral,
              characteristic.uuid == Self.notifyUUID
        else { return }
        if let error {
            failCurrent(error)
            return
        }
        guard characteristic.isNotifying else {
            failCurrent(nil)
            return
        }
        events?.bluetoothConnectionChanged(
            .connected,
            epoch: epoch,
            peripheralID: peripheral.identifier
        )
        logger.info("Notifications enabled, epoch \(self.epoch)")
        events?.bluetoothNotificationsEnabled(epoch: epoch)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral === self.peripheral,
              characteristic.uuid == Self.notifyUUID
        else { return }
        if let error {
            failCurrent(error)
            return
        }
        guard let data = characteristic.value else { return }
        events?.bluetoothReceived(data, epoch: epoch)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral === self.peripheral, error != nil else { return }
        failCurrent(error)
    }
}
