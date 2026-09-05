@preconcurrency import CoreBluetooth
import AppKit
import BluettiCore
import Foundation
import OSLog

@MainActor
protocol BluetoothCentralEvents: AnyObject {
    func bluetoothAvailabilityChanged(_ availability: BluetoothAvailability)
    func bluetoothSelectionChanged(_ selection: StationSelectionSnapshot)
    func bluetoothWillSwitchDevice()
    func bluetoothConnectionChanged(
        _ state: DeviceConnectionState,
        epoch: UInt64,
        peripheralID: UUID?
    )
    func bluetoothNotificationsEnabled(epoch: UInt64)
    func bluetoothReceived(_ data: Data, epoch: UInt64)
    func bluetoothDisconnected(epoch: UInt64, error: String?, attempt: Int)
}

protocol PeripheralSelectionStoring: AnyObject {
    var selectedPeripheralID: UUID? { get set }
}

final class UserDefaultsPeripheralSelectionStore: PeripheralSelectionStoring {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "lastPeripheralIdentifier"
    ) {
        self.defaults = defaults
        self.key = key
    }

    var selectedPeripheralID: UUID? {
        get {
            defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
        }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

@MainActor
final class BluetoothCentral: NSObject {
    static let notifyUUID = CBUUID(string: "FF01")
    static let writeUUID = CBUUID(string: "FF02")

    weak var events: BluetoothCentralEvents?

    private lazy var manager = CBCentralManager(delegate: self, queue: .main)
    private let logger = Logger(subsystem: "com.dmitry.bluetti-monitor", category: "Bluetooth")
    private let selectionStore: any PeripheralSelectionStoring
    private let initialDiscoveryDuration: TimeInterval
    private let connectionTimeout: TimeInterval
    private var selectionPolicy: StationSelectionPolicy
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var notifyCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?
    private var selectionGeneration: UInt64 = 0
    private var reconnectGeneration: UInt64 = 0
    private var connectionTimeoutGeneration: UInt64 = 0
    private var reconnectAttempt = 0
    private var pendingReconnect: PendingReconnect?
    private(set) var epoch: UInt64 = 0

    init(
        selectionStore: any PeripheralSelectionStoring = UserDefaultsPeripheralSelectionStore(),
        initialDiscoveryDuration: TimeInterval = 3,
        connectionTimeout: TimeInterval = 10
    ) {
        self.selectionStore = selectionStore
        self.initialDiscoveryDuration = initialDiscoveryDuration
        self.connectionTimeout = connectionTimeout
        selectionPolicy = StationSelectionPolicy(selectedID: selectionStore.selectedPeripheralID)
        super.init()
    }

    func start() {
        emitSelection()
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

    func markMonitoringReady(epoch expectedEpoch: UInt64) {
        guard expectedEpoch == epoch else { return }
        connectionTimeoutGeneration &+= 1
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

    func beginDeviceSelection() {
        selectionGeneration &+= 1
        selectionPolicy.beginChoosing()
        emitSelection()
        startScanIfPossible(reportConnectionState: false)
    }

    func cancelDeviceSelection() {
        guard selectionPolicy.cancelChoosing() else { return }
        selectionGeneration &+= 1
        manager.stopScan()
        emitSelection()
        if peripheral == nil {
            scanOrRestoreSelection()
        }
    }

    func rescanDeviceSelection() {
        guard selectionPolicy.mode == .choosing else { return }
        selectionGeneration &+= 1
        manager.stopScan()
        selectionPolicy.rescan()
        discoveredPeripherals.removeAll(keepingCapacity: true)
        emitSelection()
        startScanIfPossible(reportConnectionState: false)
    }

    func selectDevice(_ id: UUID) {
        guard let action = selectionPolicy.select(id) else { return }
        perform(action)
    }

    func openBluetoothPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") else { return }
        NSWorkspace.shared.open(url)
    }

    func openBluetoothControlSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
    }

    private func perform(_ action: StationSelectionAction) {
        switch action {
        case .finishSelection:
            selectionGeneration &+= 1
            manager.stopScan()
            emitSelection()
            if peripheral == nil {
                scanOrRestoreSelection()
            }
        case let .connect(id, persistSelection, resetCurrentDevice):
            guard let candidate = discoveredPeripherals[id] else {
                emitSelection()
                scanOrRestoreSelection()
                return
            }
            connect(
                candidate,
                persistSelection: persistSelection,
                resetCurrentDevice: resetCurrentDevice
            )
        }
    }

    private func connect(
        _ candidate: CBPeripheral,
        persistSelection: Bool,
        resetCurrentDevice: Bool
    ) {
        let activeIsConnectedOrConnecting = peripheral.map {
            $0.state == .connected || $0.state == .connecting
        } ?? false
        guard StationConnectionGate.canStart(
            candidateID: candidate.identifier,
            activeID: peripheral?.identifier,
            activeIsConnectedOrConnecting: activeIsConnectedOrConnecting,
            pendingCancellationID: pendingReconnect?.peripheral.identifier
        ) else {
            emitSelection()
            return
        }

        selectionGeneration &+= 1
        reconnectGeneration &+= 1
        connectionTimeoutGeneration &+= 1
        pendingReconnect = nil
        manager.stopScan()
        epoch &+= 1
        let connectionEpoch = epoch

        if let previous = peripheral {
            previous.delegate = nil
            manager.cancelPeripheralConnection(previous)
        }
        peripheral = nil
        notifyCharacteristic = nil
        writeCharacteristic = nil

        if resetCurrentDevice {
            events?.bluetoothWillSwitchDevice()
        }
        if persistSelection {
            selectionStore.selectedPeripheralID = candidate.identifier
        }

        peripheral = candidate
        candidate.delegate = self
        emitSelection()
        events?.bluetoothConnectionChanged(
            .connecting,
            epoch: connectionEpoch,
            peripheralID: candidate.identifier
        )
        logger.info("Connecting to selected PR100V2, epoch \(connectionEpoch)")
        manager.connect(candidate, options: nil)
        scheduleConnectionTimeout(epoch: connectionEpoch)
    }

    private func scanOrRestoreSelection() {
        guard manager.state == .poweredOn, pendingReconnect == nil else { return }

        if selectionPolicy.mode == .selectedOnly,
           let selectedID = selectionPolicy.selectedID
        {
            if let current = peripheral,
               current.identifier == selectedID,
               current.state == .connected || current.state == .connecting
            {
                return
            }

            if let restored = manager.retrievePeripherals(withIdentifiers: [selectedID]).first {
                discoveredPeripherals[selectedID] = restored
                let candidate = StationCandidate(
                    id: selectedID,
                    advertisedName: restored.name ?? ""
                )
                if let action = selectionPolicy.observe(candidate) {
                    emitSelection()
                    perform(action)
                    return
                }
            }
        }

        let reportConnectionState = selectionPolicy.mode != .choosing && peripheral == nil
        startScanIfPossible(reportConnectionState: reportConnectionState)
    }

    private func startScanIfPossible(reportConnectionState: Bool) {
        guard manager.state == .poweredOn else { return }
        if reportConnectionState {
            events?.bluetoothConnectionChanged(.scanning, epoch: epoch, peripheralID: nil)
        }
        manager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        if selectionPolicy.mode == .initialDiscovery {
            scheduleInitialDiscoveryDeadline()
        }
    }

    private func scheduleInitialDiscoveryDeadline() {
        selectionGeneration &+= 1
        let generation = selectionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDiscoveryDuration) { [weak self] in
            guard let self,
                  generation == self.selectionGeneration,
                  self.manager.state == .poweredOn
            else {
                return
            }
            if let action = self.selectionPolicy.finishInitialDiscovery() {
                self.perform(action)
            } else {
                self.emitSelection()
            }
        }
    }

    private func scheduleConnectionTimeout(epoch expectedEpoch: UInt64) {
        connectionTimeoutGeneration &+= 1
        let generation = connectionTimeoutGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + connectionTimeout) { [weak self] in
            guard let self,
                  generation == self.connectionTimeoutGeneration,
                  expectedEpoch == self.epoch,
                  self.peripheral != nil
            else {
                return
            }
            self.failCurrent(ConnectionLifecycleError.timeout)
        }
    }

    private func reconnect(after delay: TimeInterval) {
        reconnectGeneration &+= 1
        selectionGeneration &+= 1
        connectionTimeoutGeneration &+= 1
        let generation = reconnectGeneration
        notifyCharacteristic = nil
        writeCharacteristic = nil

        if let current = peripheral, current.state != .disconnected {
            pendingReconnect = PendingReconnect(
                peripheral: current,
                generation: generation,
                delay: delay
            )
            current.delegate = nil
            manager.cancelPeripheralConnection(current)
            return
        }

        if let current = peripheral {
            current.delegate = nil
        }
        peripheral = nil
        pendingReconnect = nil
        scheduleReconnect(generation: generation, after: delay)
    }

    private func completePendingReconnect(for ended: CBPeripheral) -> Bool {
        guard let pendingReconnect,
              pendingReconnect.peripheral === ended,
              pendingReconnect.generation == reconnectGeneration
        else {
            return false
        }
        ended.delegate = nil
        if peripheral === ended {
            peripheral = nil
        }
        self.pendingReconnect = nil
        scheduleReconnect(
            generation: pendingReconnect.generation,
            after: pendingReconnect.delay
        )
        return true
    }

    private func scheduleReconnect(generation: UInt64, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  generation == self.reconnectGeneration,
                  self.manager.state == .poweredOn
            else {
                return
            }
            self.scanOrRestoreSelection()
        }
    }

    private func failCurrent(_ error: Error?) {
        guard peripheral != nil else { return }
        let message = error?.localizedDescription
        logger.error("Connection ended, attempt \(self.reconnectAttempt + 1): \(message ?? "no detail", privacy: .public)")
        events?.bluetoothDisconnected(
            epoch: epoch,
            error: message,
            attempt: reconnectAttempt + 1
        )
        reconnectAfterFailure()
    }

    private func emitSelection() {
        events?.bluetoothSelectionChanged(selectionPolicy.snapshot)
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
            scanOrRestoreSelection()
        } else {
            selectionGeneration &+= 1
            reconnectGeneration &+= 1
            connectionTimeoutGeneration &+= 1
            manager.stopScan()
            pendingReconnect = nil
            if let peripheral {
                peripheral.delegate = nil
                manager.cancelPeripheralConnection(peripheral)
            }
            peripheral = nil
            notifyCharacteristic = nil
            writeCharacteristic = nil
            epoch &+= 1
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

        discoveredPeripherals[candidate.identifier] = candidate
        let action = selectionPolicy.observe(
            StationCandidate(id: candidate.identifier, advertisedName: name)
        )
        emitSelection()
        logger.info("Found PR100V2 candidate \(candidate.identifier.uuidString, privacy: .private(mask: .hash))")
        if let action {
            perform(action)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect connected: CBPeripheral) {
        if let pendingReconnect, pendingReconnect.peripheral === connected {
            manager.cancelPeripheralConnection(connected)
            return
        }
        guard connected === peripheral else { return }
        connected.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect failed: CBPeripheral,
        error: Error?
    ) {
        if completePendingReconnect(for: failed) { return }
        guard failed === peripheral else { return }
        failCurrent(error)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral disconnected: CBPeripheral,
        error: Error?
    ) {
        if completePendingReconnect(for: disconnected) { return }
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

private struct PendingReconnect {
    let peripheral: CBPeripheral
    let generation: UInt64
    let delay: TimeInterval
}

private enum ConnectionLifecycleError: LocalizedError {
    case timeout

    var errorDescription: String? {
        switch self {
        case .timeout:
            "Подключение не завершилось за 10 секунд"
        }
    }
}
