import Foundation

public enum LanguagePreference: Equatable, Hashable, Sendable {
    case system
    case language(String)
}

public enum AppearancePreference: String, CaseIterable, Equatable, Hashable, Sendable {
    case system
    case light
    case dark
}

public struct LanguageOption: Equatable, Identifiable, Sendable {
    public let identifier: String
    public let nativeName: String

    public var id: String { identifier }

    public init(identifier: String, nativeName: String) {
        self.identifier = identifier
        self.nativeName = nativeName
    }
}

public struct AppLocalizer: @unchecked Sendable {
    public static var resourceBundleURL: URL { defaultResourceBundle.bundleURL }
    public static var availableLanguageOptions: [LanguageOption] {
        availableLanguageOptions(in: defaultResourceBundle)
    }

    public let resolvedLanguage: String
    public let locale: Locale
    public let bundleURL: URL

    private let localizedBundle: Bundle
    private let englishBundle: Bundle?

    public init(
        language: LanguagePreference = .system,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.init(
            language: language,
            preferredLanguages: preferredLanguages,
            bundle: Self.defaultResourceBundle
        )
    }

    public init(
        language: LanguagePreference,
        preferredLanguages: [String] = Locale.preferredLanguages,
        bundle: Bundle
    ) {
        let supported = Self.supportedLanguages(in: bundle)
        let requested: [String]
        switch language {
        case .system:
            requested = preferredLanguages
        case let .language(identifier):
            requested = [identifier]
        }

        let selected = Bundle.preferredLocalizations(
            from: supported,
            forPreferences: requested
        ).first
        let resolved = selected.flatMap { supported.contains($0) ? $0 : nil }
            ?? supported.first(where: { $0.caseInsensitiveCompare("en") == .orderedSame })
            ?? "en"

        resolvedLanguage = resolved
        locale = Locale(identifier: resolved)
        bundleURL = bundle.bundleURL
        localizedBundle = Self.localizationBundle(for: resolved, in: bundle) ?? bundle
        englishBundle = Self.localizationBundle(for: "en", in: bundle)
    }

    public func text(_ key: String) -> String {
        let localized = localizedBundle.localizedString(
            forKey: key,
            value: nil,
            table: nil
        )
        if localized != key { return localized }
        guard let englishBundle else { return localized }
        return englishBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    public func format(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    public func minutes(_ count: Int) -> String {
        format("duration.minutes", Int64(count))
    }

    public func hours(_ count: Int) -> String {
        format("duration.hours", Int64(count))
    }

    public static func availableLanguageOptions(in bundle: Bundle) -> [LanguageOption] {
        supportedLanguages(in: bundle).map { identifier in
            let locale = Locale(identifier: identifier)
            let rawName = locale.localizedString(forLanguageCode: identifier) ?? identifier
            return LanguageOption(
                identifier: identifier,
                nativeName: rawName.capitalized(with: locale)
            )
        }
    }

    private static func supportedLanguages(in bundle: Bundle) -> [String] {
        Array(Set(bundle.localizations.filter {
            !$0.isEmpty && $0.caseInsensitiveCompare("Base") != .orderedSame
        }))
            .sorted { lhs, rhs in
                if lhs == "en" { return true }
                if rhs == "en" { return false }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }

    private static func localizationBundle(for identifier: String, in bundle: Bundle) -> Bundle? {
        guard let path = bundle.path(forResource: identifier, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    private static var defaultResourceBundle: Bundle {
        if let resources = Bundle.main.resourceURL,
           let packaged = Bundle(
               url: resources.appendingPathComponent("BluettiMonitor_BluettiCore.bundle")
           )
        {
            return packaged
        }
        return .module
    }
}

public final class AppPreferencesStore: @unchecked Sendable {
    public static let languageKey = "preferredLanguage"
    public static let appearanceKey = "preferredAppearance"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var language: LanguagePreference {
        get {
            guard let identifier = defaults.string(forKey: Self.languageKey),
                  !identifier.isEmpty
            else {
                return .system
            }
            return .language(identifier)
        }
        set {
            switch newValue {
            case .system:
                defaults.removeObject(forKey: Self.languageKey)
            case let .language(identifier):
                guard !identifier.isEmpty else {
                    defaults.removeObject(forKey: Self.languageKey)
                    return
                }
                defaults.set(identifier, forKey: Self.languageKey)
            }
        }
    }

    public var appearance: AppearancePreference {
        get {
            guard let rawValue = defaults.string(forKey: Self.appearanceKey),
                  let value = AppearancePreference(rawValue: rawValue)
            else {
                return .system
            }
            return value
        }
        set {
            if newValue == .system {
                defaults.removeObject(forKey: Self.appearanceKey)
            } else {
                defaults.set(newValue.rawValue, forKey: Self.appearanceKey)
            }
        }
    }
}
