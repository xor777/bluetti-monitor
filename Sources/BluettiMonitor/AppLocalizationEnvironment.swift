import AppKit
import BluettiCore
import SwiftUI

private struct AppLocalizerEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppLocalizer()
}

extension EnvironmentValues {
    var appLocalizer: AppLocalizer {
        get { self[AppLocalizerEnvironmentKey.self] }
        set { self[AppLocalizerEnvironmentKey.self] = newValue }
    }
}

extension AppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var appKitAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
