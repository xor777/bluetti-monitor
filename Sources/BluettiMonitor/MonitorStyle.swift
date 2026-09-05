import AppKit
import BluettiCore
import SwiftUI

enum MonitorStyle {
    static let width: CGFloat = 380
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 14
    static let compactSpacing: CGFloat = 8
    static let sectionRadius: CGFloat = 10

    static let accent = adaptiveColor(
        light: NSColor(srgbRed: 0.00, green: 0.48, blue: 0.31, alpha: 1),
        dark: NSColor(srgbRed: 0.12, green: 0.68, blue: 0.46, alpha: 1)
    )
    static let batteryWarning = adaptiveColor(
        light: NSColor(srgbRed: 0.68, green: 0.35, blue: 0.00, alpha: 1),
        dark: .systemOrange
    )

    static func color(for tone: StatusTone) -> Color {
        switch tone {
        case .good: accent
        case .warning: .orange
        case .unavailable, .neutral: .secondary
        }
    }

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
