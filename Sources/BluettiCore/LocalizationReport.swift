import Foundation

public struct LocalizationReport: Codable, Equatable, Sendable {
    public let requestedLanguages: [String]
    public let resolvedLanguage: String
    public let availableLanguages: [String]
    public let resourceBundleURL: String
    public let settingsTitle: String
    public let statusTitle: String
    public let notificationTitle: String

    public init(preferredLanguages: [String]) {
        let localizer = AppLocalizer(
            language: .system,
            preferredLanguages: preferredLanguages
        )
        requestedLanguages = preferredLanguages
        resolvedLanguage = localizer.resolvedLanguage
        availableLanguages = AppLocalizer.availableLanguageOptions.map(\.identifier)
        resourceBundleURL = localizer.bundleURL.absoluteString
        settingsTitle = localizer.text("settings.title")
        statusTitle = StatusPresentation.make(
            .init(bluetooth: .poweredOff),
            localizer: localizer
        ).title
        notificationTitle = NotificationEvent.powerLost(batteryPercent: nil)
            .content(using: localizer)
            .title
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
