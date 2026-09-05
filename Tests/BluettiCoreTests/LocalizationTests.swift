import BluettiCore
import Foundation

func localizationTests() -> [TestCase] {
    [
        ("system language follows the first supported OS preference", {
            let russian = AppLocalizer(
                language: .system,
                preferredLanguages: ["fr-FR", "ru-RU"]
            )
            let english = AppLocalizer(
                language: .system,
                preferredLanguages: ["en-GB", "ru-RU"]
            )

            try expectEqual(russian.resolvedLanguage, "ru")
            try expectEqual(russian.text("settings.title"), "Настройки")
            try expectEqual(english.resolvedLanguage, "en")
            try expectEqual(english.text("settings.title"), "Settings")
        }),
        ("unsupported system and manual languages fall back to English", {
            let system = AppLocalizer(
                language: .system,
                preferredLanguages: ["de-DE"]
            )
            let manual = AppLocalizer(
                language: .language("de"),
                preferredLanguages: ["ru-RU"]
            )

            try expectEqual(system.resolvedLanguage, "en")
            try expectEqual(manual.resolvedLanguage, "en")
            try expectEqual(manual.text("settings.appearance.dark"), "Dark")
        }),
        ("manual language overrides OS preferences immediately", {
            let russian = AppLocalizer(
                language: .language("ru"),
                preferredLanguages: ["en-US"]
            )
            let english = AppLocalizer(
                language: .language("en"),
                preferredLanguages: ["ru-RU"]
            )

            try expectEqual(russian.text("settings.language.label"), "Язык")
            try expectEqual(english.text("settings.language.label"), "Language")
        }),
        ("language options are discovered from packaged resources", {
            let options = AppLocalizer.availableLanguageOptions

            try expectEqual(Set(options.map(\.identifier)).count, options.count)
            let names = Dictionary(uniqueKeysWithValues: options.map {
                ($0.identifier, $0.nativeName)
            })
            try expectEqual(names["en"], "English")
            try expectEqual(names["ru"], "Русский")
            guard AppLocalizer.resourceBundleURL.pathExtension == "bundle" else {
                throw TestFailure(description: "Expected a SwiftPM resource bundle URL")
            }
        }),
        ("a standard third locale is discovered and selected without code changes", {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("BluettiLocalizationFixture-\(UUID().uuidString).bundle")
            defer { try? FileManager.default.removeItem(at: root) }
            let resources = root.appendingPathComponent("Contents/Resources")
            for language in ["en", "fr"] {
                let directory = resources.appendingPathComponent("\(language).lproj")
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                let value = language == "fr" ? "Réglages" : "Settings"
                try "\"settings.title\" = \"\(value)\";\n".write(
                    to: directory.appendingPathComponent("Localizable.strings"),
                    atomically: true,
                    encoding: .utf8
                )
            }
            let info: [String: Any] = [
                "CFBundleIdentifier": "com.dmitry.bluetti-monitor.localization-fixture",
                "CFBundleDevelopmentRegion": "en",
                "CFBundleLocalizations": ["en", "fr"],
            ]
            let infoData = try PropertyListSerialization.data(
                fromPropertyList: info,
                format: .xml,
                options: 0
            )
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Contents"),
                withIntermediateDirectories: true
            )
            try infoData.write(to: root.appendingPathComponent("Contents/Info.plist"))
            guard let bundle = Bundle(url: root) else {
                throw TestFailure(description: "Could not load localization fixture bundle")
            }

            let options = AppLocalizer.availableLanguageOptions(in: bundle)
            let system = AppLocalizer(
                language: .system,
                preferredLanguages: ["fr-FR"],
                bundle: bundle
            )
            let explicit = AppLocalizer(
                language: .language("fr"),
                preferredLanguages: ["en-US"],
                bundle: bundle
            )

            try expectEqual(options.map(\.identifier), ["en", "fr"])
            try expectEqual(system.resolvedLanguage, "fr")
            try expectEqual(explicit.text("settings.title"), "Réglages")
        }),
        ("localized duration uses native plural resources", {
            let english = AppLocalizer(language: .language("en"))
            let russian = AppLocalizer(language: .language("ru"))

            try expectEqual(english.minutes(1), "1 minute")
            try expectEqual(english.minutes(2), "2 minutes")
            try expectEqual(russian.minutes(1), "1 минута")
            try expectEqual(russian.minutes(2), "2 минуты")
            try expectEqual(russian.minutes(5), "5 минут")
            try expectEqual(english.hours(1), "1 hour")
            try expectEqual(english.hours(2), "2 hours")
            try expectEqual(russian.hours(1), "1 час")
            try expectEqual(russian.hours(2), "2 часа")
            try expectEqual(russian.hours(5), "5 часов")
        }),
        ("status and readiness presentations use the requested language", {
            let english = AppLocalizer(language: .language("en"))
            let status = StatusPresentation.make(
                .init(bluetooth: .poweredOff),
                localizer: english
            )
            let readiness = NotificationReadinessPresentation.make(
                .denied,
                localizer: english
            )

            try expectEqual(status.title, "Bluetooth is off")
            try expectEqual(status.subtitle, "Monitoring paused")
            try expectEqual(readiness.title, "Notifications are blocked")
            try expectEqual(readiness.detail, "Allow them in macOS Settings")
        }),
        ("notification content is formed in the active language at delivery time", {
            let event = NotificationEvent.lowBattery(batteryPercent: 20)
            let russian = event.content(using: AppLocalizer(language: .language("ru")))
            let english = event.content(using: AppLocalizer(language: .language("en")))

            try expectEqual(russian.title, "Низкий заряд станции")
            try expectEqual(russian.body, "Заряд станции: 20%. Сохраните работу.")
            try expectEqual(english.title, "Low station battery")
            try expectEqual(english.body, "Station charge: 20%. Save your work.")
        }),
        ("structured app errors relocalize while preserving technical detail", {
            let error = UserFacingError.notificationSchedulingFailed("UNErrorDomain 1")

            try expectEqual(
                error.localized(using: AppLocalizer(language: .language("ru"))),
                "Не удалось запланировать уведомление: UNErrorDomain 1"
            )
            try expectEqual(
                error.localized(using: AppLocalizer(language: .language("en"))),
                "Could not schedule notification: UNErrorDomain 1"
            )
            try expectEqual(error.diagnosticDetail, "UNErrorDomain 1")
        }),
        ("machine-readable report contains resolved localized behavior and bundle path", {
            let report = LocalizationReport(preferredLanguages: ["ru-RU"])
            let object = try JSONSerialization.jsonObject(with: report.jsonData())
            guard let json = object as? [String: Any] else {
                throw TestFailure(description: "Localization report was not a JSON object")
            }

            try expectEqual(report.resolvedLanguage, "ru")
            try expectEqual(report.settingsTitle, "Настройки")
            try expectEqual(report.statusTitle, "Bluetooth выключен")
            try expectEqual(report.notificationTitle, "Питание пропало")
            try expectEqual(json["resolvedLanguage"] as? String, "ru")
            try expectEqual(
                json["resourceBundleURL"] as? String,
                AppLocalizer.resourceBundleURL.absoluteString
            )
        }),
        ("every shipped locale has the same strings and format placeholders", {
            let languages = AppLocalizer.availableLanguageOptions.map(\.identifier)
            guard let reference = try localizationStrings(language: "en") else {
                throw TestFailure(description: "Missing English localization fixture")
            }
            let referencePlurals = try localizationPlurals(language: "en")

            for language in languages {
                guard let localized = try localizationStrings(language: language) else {
                    throw TestFailure(description: "Missing strings for \(language)")
                }
                try expectEqual(Set(localized.keys), Set(reference.keys), "locale \(language)")
                for key in reference.keys {
                    try expectEqual(
                        formatPlaceholders(in: localized[key] ?? ""),
                        formatPlaceholders(in: reference[key] ?? ""),
                        "key \(key), locale \(language)"
                    )
                }
                try expectEqual(
                    try localizationPlurals(language: language),
                    referencePlurals,
                    "plural keys, locale \(language)"
                )
            }
        }),
    ]
}

private func localizationStrings(language: String) throws -> [String: String]? {
    let url = AppLocalizer.resourceBundleURL
        .appendingPathComponent("\(language).lproj/Localizable.strings")
    let data = try Data(contentsOf: url)
    return try PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
    ) as? [String: String]
}

private func localizationPlurals(language: String) throws -> Set<String> {
    let url = AppLocalizer.resourceBundleURL
        .appendingPathComponent("\(language).lproj/Localizable.stringsdict")
    let data = try Data(contentsOf: url)
    let value = try PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
    ) as? [String: Any]
    return Set(value?.keys.map { $0 } ?? [])
}

private func formatPlaceholders(in value: String) -> [String] {
    let expression = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(?:ll)?[@df]"#)
    let range = NSRange(value.startIndex..., in: value)
    return expression.matches(in: value, range: range).compactMap { match in
        Range(match.range, in: value).map { String(value[$0]) }
    }
}

func preferenceTests() -> [TestCase] {
    [
        ("language and appearance preferences default to System and persist", {
            let suite = "BluettiCoreTests.preferences.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else {
                throw TestFailure(description: "Could not create isolated UserDefaults")
            }
            defer { defaults.removePersistentDomain(forName: suite) }

            let store = AppPreferencesStore(defaults: defaults)
            try expectEqual(store.language, .system)
            try expectEqual(store.appearance, .system)

            store.language = .language("ru")
            store.appearance = .dark

            let restored = AppPreferencesStore(defaults: defaults)
            try expectEqual(restored.language, .language("ru"))
            try expectEqual(restored.appearance, .dark)

            restored.language = .system
            restored.appearance = .system
            try expectEqual(defaults.object(forKey: AppPreferencesStore.languageKey) == nil, true)
            try expectEqual(defaults.object(forKey: AppPreferencesStore.appearanceKey) == nil, true)
        }),
        ("invalid stored preference values safely reset to System", {
            let suite = "BluettiCoreTests.invalid-preferences.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else {
                throw TestFailure(description: "Could not create isolated UserDefaults")
            }
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set("", forKey: AppPreferencesStore.languageKey)
            defaults.set("sepia", forKey: AppPreferencesStore.appearanceKey)

            let store = AppPreferencesStore(defaults: defaults)
            try expectEqual(store.language, .system)
            try expectEqual(store.appearance, .system)
        }),
    ]
}
