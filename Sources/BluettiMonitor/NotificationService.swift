@preconcurrency import UserNotifications
import AppKit
import BluettiCore
import Foundation
import OSLog

@MainActor
protocol NotificationServicing: AnyObject {
    var healthChanged: ((NotificationHealth) -> Void)? { get set }
    var schedulingFailed: ((String) -> Void)? { get set }

    func prepare() async
    func requestAuthorization() async throws -> NotificationHealth
    func refreshHealth() async
    func deliver(_ event: NotificationEvent, localizer: AppLocalizer)
    func schedule(_ event: NotificationEvent, localizer: AppLocalizer) async throws
    func openSettings()
}

@MainActor
final class NotificationService: NSObject, NotificationServicing {
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.dmitry.bluetti-monitor", category: "Notifications")
    var healthChanged: ((NotificationHealth) -> Void)?
    var schedulingFailed: ((String) -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    func prepare() async {
        healthChanged?(health(from: await center.notificationSettings()))
    }

    @discardableResult
    func requestAuthorization() async throws -> NotificationHealth {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            healthChanged?(health(from: await center.notificationSettings()))
            throw error
        }
        let settings = await center.notificationSettings()
        let value = health(from: settings)
        healthChanged?(value)
        return value
    }

    func refreshHealth() async {
        healthChanged?(health(from: await center.notificationSettings()))
    }

    func deliver(_ event: NotificationEvent, localizer: AppLocalizer) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await schedule(event, localizer: localizer)
            } catch {
                logger.error("Notification failed: \(String(describing: error), privacy: .public)")
                schedulingFailed?(error.localizedDescription)
            }
        }
    }

    func schedule(_ event: NotificationEvent, localizer: AppLocalizer) async throws {
        let localized = event.content(using: localizer)
        let request = makeRequest(event, content: localized)
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            center.add(request) { [logger] error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    logger.info("Notification scheduled: \(localized.title, privacy: .public)")
                    continuation.resume()
                }
            }
        }
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func makeRequest(
        _ event: NotificationEvent,
        content localized: LocalizedNotificationContent
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = localized.title
        if let body = localized.body {
            content.body = body
        }
        if event.playsSound { content.sound = .default }
        content.interruptionLevel = .active
        return UNNotificationRequest(
            identifier: "\(event)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
    }

    private func health(from settings: UNNotificationSettings) -> NotificationHealth {
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional:
            break
        @unknown default:
            return .unknown
        }
        switch settings.alertSetting {
        case .enabled:
            return .available
        case .disabled, .notSupported:
            return .alertsDisabled
        @unknown default:
            return .unknown
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
