import BluettiCore
import Foundation
import OSLog

@MainActor
final class BluettiDeviceSession: BluetoothCentralEvents {
    private let central: BluetoothCentral
    private weak var model: AppModel?
    private var handshake = V2Handshake()
    private var frameStream = V2FrameStream()
    private var coordinator = RequestCoordinator(timeout: 1.5)
    private var powerDetector = PowerStateDetector()
    private let timing = MonitoringTiming()
    private let logger = Logger(subsystem: "com.dmitry.bluetti-monitor", category: "Session")

    private var activeEpoch: UInt64 = 0
    private var monitorTask: Task<Void, Never>?
    private var handshakeReadyAt: TimeInterval?
    private var lastVoltageAt: TimeInterval?
    private var nextVoltageAt: TimeInterval = 0
    private var nextTelemetryAt: TimeInterval = 0
    private var telemetryQueue: [ModbusRead] = []
    private var readinessAnnounced = false
    private var freshness: DataFreshness = .lost

    init(central: BluetoothCentral, model: AppModel) {
        self.central = central
        self.model = model
        central.events = self
    }

    func start() {
        central.start()
    }

    func reconnect() {
        endMonitoring()
        central.reconnectImmediately()
    }

    func refreshImmediately() {
        nextVoltageAt = ProcessInfo.processInfo.systemUptime
    }

    func bluetoothAvailabilityChanged(_ availability: BluetoothAvailability) {
        model?.setBluetooth(availability)
        if availability != .poweredOn {
            monitoringGap(error: nil)
        }
    }

    func bluetoothConnectionChanged(
        _ state: DeviceConnectionState,
        epoch: UInt64,
        peripheralID: UUID?
    ) {
        model?.setCentralConnection(state, peripheralID: peripheralID)
        if state == .connecting {
            begin(epoch: epoch)
        }
    }

    func bluetoothNotificationsEnabled(epoch: UInt64) {
        guard epoch == activeEpoch else { return }
        handshake.notificationsEnabled()
        logger.info("Handshake waiting for challenge, epoch \(epoch)")
    }

    func bluetoothReceived(_ data: Data, epoch: UInt64) {
        guard epoch == activeEpoch else { return }
        do {
            for frame in try frameStream.append(data) {
                try process(frame, epoch: epoch)
            }
        } catch {
            failSession("Ошибка протокола: \(short(error))")
        }
    }

    func bluetoothDisconnected(epoch: UInt64, error: String?, attempt: Int) {
        guard epoch == activeEpoch else { return }
        let message: String?
        if attempt >= 3 {
            message = "Проверьте, не подключено ли приложение BLUETTI"
        } else {
            message = error
        }
        monitoringGap(error: message)
    }

    private func begin(epoch: UInt64) {
        endMonitoring()
        activeEpoch = epoch
        handshake = V2Handshake()
        frameStream = V2FrameStream(encryptedHeader: .fixedIV)
        coordinator.reset()
        powerDetector.resetCandidate()
        readinessAnnounced = false
        freshness = .lost
    }

    private func process(_ frame: V2WireFrame, epoch: UInt64) throws {
        if handshake.state != .ready {
            logger.info("Handshake frame \(self.handshakeSummary(frame), privacy: .public), state \(String(describing: self.handshake.state), privacy: .public)")
            let action: V2HandshakeAction
            switch frame {
            case let .preKey(data):
                action = try handshake.receive(data)
            case let .encrypted(data):
                action = try handshake.receive(data, encrypted: true)
            }
            switch action {
            case .none:
                break
            case let .write(data):
                logger.info("Handshake reply, stage \(String(describing: self.handshake.state), privacy: .public)")
                guard central.write(data, epoch: epoch) else {
                    throw SessionError.writeUnavailable
                }
            case .ready:
                logger.info("Secure session ready, epoch \(epoch)")
                frameStream.encryptedHeader = .dynamicIV
                startMonitoring()
            }
            return
        }

        guard case let .encrypted(envelope) = frame,
              let secureKey = handshake.secureKey
        else {
            throw SessionError.unexpectedFrame
        }
        let pendingRead = coordinator.pendingRead
        let plaintext = try V2Crypto.decrypt(envelope, key: secureKey)
        let now = ProcessInfo.processInfo.systemUptime
        let patch = try coordinator.receive(plaintext, epoch: epoch, now: now)
        model?.apply(patch)

        if pendingRead == PR100V2TelemetryDecoder.acInputVoltage,
           let voltage = patch.acInputVoltage
        {
            logger.info("AC input voltage \(voltage, format: .fixed(precision: 1)) V")
            lastVoltageAt = now
            setFreshness(.fresh)
            if !readinessAnnounced {
                readinessAnnounced = true
                central.markMonitoringReady()
                model?.monitoringReady()
            }
            if let transition = powerDetector.observe(voltage: voltage) {
                logger.notice("Power transition: \(String(describing: transition), privacy: .public)")
                model?.handle(transition)
            }
        } else if let soc = patch.batteryPercent {
            logger.info("Battery \(soc)%")
        } else if let watts = patch.acInputPower {
            logger.info("AC input \(watts) W")
        } else if let watts = patch.acOutputPower {
            logger.info("AC output \(watts) W")
        }
    }

    private func startMonitoring() {
        let now = ProcessInfo.processInfo.systemUptime
        handshakeReadyAt = now
        lastVoltageAt = nil
        nextVoltageAt = now
        nextTelemetryAt = now
        telemetryQueue = [
            PR100V2TelemetryDecoder.model,
            PR100V2TelemetryDecoder.batteryPercent,
            PR100V2TelemetryDecoder.acInputPower,
            PR100V2TelemetryDecoder.acOutputPower,
        ]
        monitorTask?.cancel()
        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func tick() {
        guard handshake.state == .ready else { return }
        let now = ProcessInfo.processInfo.systemUptime

        if coordinator.expireIfNeeded(now: now) {
            model?.noteError("Нет ответа от устройства")
        }

        let sampleOrigin = lastVoltageAt ?? handshakeReadyAt
        if let sampleOrigin {
            let newFreshness = timing.freshness(age: now - sampleOrigin)
            setFreshness(newFreshness)
            if newFreshness == .lost {
                failSession("Нет данных от устройства")
                return
            }
        }

        guard !coordinator.isBusy else { return }
        if now >= nextVoltageAt {
            nextVoltageAt = anchoredNext(after: nextVoltageAt, interval: 0.5, now: now)
            send(PR100V2TelemetryDecoder.acInputVoltage, now: now)
            return
        }
        if now >= nextTelemetryAt {
            nextTelemetryAt = anchoredNext(after: nextTelemetryAt, interval: 2, now: now)
            telemetryQueue.append(contentsOf: [
                PR100V2TelemetryDecoder.batteryPercent,
                PR100V2TelemetryDecoder.acInputPower,
                PR100V2TelemetryDecoder.acOutputPower,
            ])
        }
        if !telemetryQueue.isEmpty {
            send(telemetryQueue.removeFirst(), now: now)
        }
    }

    private func send(_ read: ModbusRead, now: TimeInterval) {
        do {
            guard let secureKey = handshake.secureKey else { throw SessionError.notReady }
            let request = try coordinator.begin(read, epoch: activeEpoch, now: now)
            let envelope = try V2Crypto.encrypt(request, key: secureKey)
            guard central.write(envelope, epoch: activeEpoch) else {
                coordinator.reset()
                throw SessionError.writeUnavailable
            }
        } catch {
            coordinator.reset()
            model?.noteError(short(error))
        }
    }

    private func anchoredNext(
        after previous: TimeInterval,
        interval: TimeInterval,
        now: TimeInterval
    ) -> TimeInterval {
        var next = previous + interval
        while next <= now { next += interval }
        return next
    }

    private func setFreshness(_ value: DataFreshness) {
        guard value != freshness else { return }
        freshness = value
        model?.setFreshness(value)
    }

    private func failSession(_ message: String) {
        logger.error("Session failed: \(message, privacy: .public)")
        monitoringGap(error: message)
        central.reconnectAfterFailure()
    }

    private func monitoringGap(error: String?) {
        endMonitoring()
        powerDetector.resetCandidate()
        model?.monitoringLost(error: error)
    }

    private func endMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        coordinator.reset()
        frameStream.reset()
        handshakeReadyAt = nil
        lastVoltageAt = nil
        telemetryQueue.removeAll(keepingCapacity: true)
        readinessAnnounced = false
    }

    private func short(_ error: Error) -> String {
        String(describing: error)
    }

    private func handshakeSummary(_ frame: V2WireFrame) -> String {
        do {
            let plaintext: Data
            let encrypted: Bool
            switch frame {
            case let .preKey(data):
                plaintext = data
                encrypted = false
            case let .encrypted(data):
                guard let key = handshake.insecureKey, let iv = handshake.insecureIV else {
                    return "encrypted before challenge"
                }
                plaintext = try V2Crypto.decrypt(data, key: key, fixedIV: iv)
                encrypted = true
            }
            let message = try V2PreKeyMessage.parse(plaintext)
            return "type \(message.type), data \(message.data.count) bytes, encrypted \(encrypted)"
        } catch {
            return "unreadable frame"
        }
    }
}

private enum SessionError: Error {
    case notReady
    case writeUnavailable
    case unexpectedFrame
}
