@preconcurrency import UserNotifications
import AppKit
import BluettiCore
import Foundation
import OSLog

enum NotificationHealth: Equatable, Sendable {
    case unknown
    case available
    case unavailable
}

@MainActor
final class NotificationService: NSObject {
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.dmitry.bluetti-monitor", category: "Notifications")
    var healthChanged: ((NotificationHealth) -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    func prepare() async {
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        healthChanged?(health(from: settings))
    }

    func refreshHealth() async {
        healthChanged?(health(from: await center.notificationSettings()))
    }

    func deliver(_ event: NotificationEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.text
        if event.playsSound { content.sound = .default }
        content.interruptionLevel = .active
        let request = UNNotificationRequest(
            identifier: "\(event)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request) { [logger] error in
            if let error {
                logger.error("Notification failed: \(String(describing: error), privacy: .public)")
            } else {
                logger.info("Notification delivered: \(event.text, privacy: .public)")
            }
        }
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func health(from settings: UNNotificationSettings) -> NotificationHealth {
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return .unavailable
        }
        guard settings.alertSetting == .enabled else { return .unavailable }
        return .available
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
