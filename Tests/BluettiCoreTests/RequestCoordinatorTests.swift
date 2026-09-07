import BluettiCore
import Foundation

func requestCoordinatorTests() -> [TestCase] {
    [
        ("coordinator permits exactly one request in flight", {
            var coordinator = RequestCoordinator(timeout: 1.5)
            _ = try coordinator.begin(.init(startAddress: 102, quantity: 1), epoch: 7, now: 10)
            try expectThrows(RequestCoordinatorError.busy) {
                try coordinator.begin(.init(startAddress: 146, quantity: 1), epoch: 7, now: 10)
            }
        }),
        ("response decodes against the pending register and clears it", {
            var coordinator = RequestCoordinator(timeout: 1.5)
            _ = try coordinator.begin(.init(startAddress: 102, quantity: 1), epoch: 7, now: 10)
            let response = Data([0x01, 0x03, 0x02, 0x00, 0x64, 0xB9, 0xAF])
            let patch = try coordinator.receive(response, epoch: 7, now: 10.2)
            try expectEqual(patch.batteryPercent, 100)
            try expectThrows(RequestCoordinatorError.noPendingRequest) {
                try coordinator.receive(response, epoch: 7, now: 10.3)
            }
        }),
        ("old epoch response is rejected and cannot consume current request", {
            var coordinator = RequestCoordinator(timeout: 1.5)
            _ = try coordinator.begin(.init(startAddress: 102, quantity: 1), epoch: 8, now: 10)
            let response = Data([0x01, 0x03, 0x02, 0x00, 0x64, 0xB9, 0xAF])
            try expectThrows(RequestCoordinatorError.wrongEpoch) {
                try coordinator.receive(response, epoch: 7, now: 10.2)
            }
            try expectEqual(try coordinator.receive(response, epoch: 8, now: 10.3).batteryPercent, 100)
        }),
        ("late response expires and clears pending request", {
            var coordinator = RequestCoordinator(timeout: 1.5)
            _ = try coordinator.begin(.init(startAddress: 102, quantity: 1), epoch: 8, now: 10)
            let response = Data([0x01, 0x03, 0x02, 0x00, 0x64, 0xB9, 0xAF])
            try expectThrows(RequestCoordinatorError.timedOut) {
                try coordinator.receive(response, epoch: 8, now: 11.5)
            }
            try expectThrows(RequestCoordinatorError.noPendingRequest) {
                try coordinator.receive(response, epoch: 8, now: 11.6)
            }
        }),
        ("expiration identifies the read that needs a protocol barrier", {
            var coordinator = RequestCoordinator(timeout: 1.5)
            let runtime = ModbusRead(startAddress: 104, quantity: 1)
            _ = try coordinator.begin(runtime, epoch: 8, now: 10)

            try expectNil(coordinator.expiredReadIfNeeded(now: 11.49))
            try expectEqual(coordinator.expiredReadIfNeeded(now: 11.5), runtime)
            try expectNil(coordinator.expiredReadIfNeeded(now: 11.6))
        }),
        ("reset drops pending request after disconnect", {
            var coordinator = RequestCoordinator(timeout: 1.5)
            _ = try coordinator.begin(.init(startAddress: 102, quantity: 1), epoch: 8, now: 10)
            coordinator.reset()
            let response = Data([0x01, 0x03, 0x02, 0x00, 0x64, 0xB9, 0xAF])
            try expectThrows(RequestCoordinatorError.noPendingRequest) {
                try coordinator.receive(response, epoch: 8, now: 10.1)
            }
        }),
    ]
}
