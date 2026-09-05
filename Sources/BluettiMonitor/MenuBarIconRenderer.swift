import AppKit
import BluettiCore

enum MenuBarIconRenderer {
    private static let size = NSSize(width: 20, height: 18)

    static func image(
        for state: MenuBarPresentation.Icon,
        accessibilityDescription: String
    ) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            NSGraphicsContext.current?.shouldAntialias = true
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let body = NSBezierPath(
                roundedRect: NSRect(x: 1.4, y: 1.7, width: 17.2, height: 14.6),
                xRadius: 4.2,
                yRadius: 4.2
            )
            body.lineWidth = 1.8
            body.stroke()

            switch state {
            case .online:
                boltPath().fill()
            case .backup:
                pulsePath().stroke()
            case .stale:
                exclamationPath().stroke()
            case .unavailable:
                slashPath().stroke()
            case .searching:
                dotsPath().fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    private static func boltPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 10.9, y: 14.2))
        path.line(to: NSPoint(x: 6.9, y: 8.8))
        path.line(to: NSPoint(x: 9.4, y: 8.8))
        path.line(to: NSPoint(x: 8.8, y: 3.9))
        path.line(to: NSPoint(x: 13.3, y: 9.8))
        path.line(to: NSPoint(x: 10.6, y: 9.8))
        path.close()
        return path
    }

    private static func pulsePath() -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: 5.2, y: 8.8))
        path.line(to: NSPoint(x: 7.8, y: 8.8))
        path.line(to: NSPoint(x: 9.1, y: 11.8))
        path.line(to: NSPoint(x: 10.8, y: 5.8))
        path.line(to: NSPoint(x: 12.0, y: 8.8))
        path.line(to: NSPoint(x: 14.8, y: 8.8))
        return path
    }

    private static func exclamationPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = 2.0
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: 10, y: 12.6))
        path.line(to: NSPoint(x: 10, y: 8.0))
        path.move(to: NSPoint(x: 10, y: 5.3))
        path.line(to: NSPoint(x: 10, y: 5.2))
        return path
    }

    private static func slashPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = 2.0
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: 5.8, y: 13.0))
        path.line(to: NSPoint(x: 14.2, y: 5.0))
        return path
    }

    private static func dotsPath() -> NSBezierPath {
        let path = NSBezierPath()
        for x in [7.0, 10.0, 13.0] {
            path.appendOval(in: NSRect(x: x - 0.9, y: 8.1, width: 1.8, height: 1.8))
        }
        return path
    }
}
