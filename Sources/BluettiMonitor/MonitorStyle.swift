import BluettiCore
import SwiftUI

enum MonitorStyle {
    static let width: CGFloat = 440
    static let horizontalPadding: CGFloat = 18
    static let verticalPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 16
    static let compactSpacing: CGFloat = 8
    static let sectionRadius: CGFloat = 12

    static let accent = Color(red: 0.25, green: 0.82, blue: 0.57)

    static func color(for tone: StatusTone) -> Color {
        switch tone {
        case .good: accent
        case .warning: .orange
        case .unavailable, .neutral: .secondary
        }
    }
}
