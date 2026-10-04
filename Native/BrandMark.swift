import AppKit

enum QuietSpeakIcon {
    static func draw(in bounds: NSRect, color: NSColor) {
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: bounds.minX + x * bounds.width, y: bounds.minY + y * bounds.height)
        }
        color.setStroke()
        color.setFill()
        let outline = NSBezierPath(
            roundedRect: NSRect(
                x: bounds.minX + bounds.width * 0.08, y: bounds.minY + bounds.height * 0.18,
                width: bounds.width * 0.76, height: bounds.height * 0.76),
            xRadius: bounds.width * 0.22, yRadius: bounds.height * 0.22)
        outline.lineWidth = bounds.width * 0.075
        outline.stroke()
        let tail = NSBezierPath()
        tail.move(to: point(0.65, 0.24))
        tail.line(to: point(0.90, 0.06))
        tail.lineWidth = bounds.width * 0.075
        tail.lineCapStyle = .round
        tail.stroke()
        for (index, height) in [CGFloat(0.24), 0.42, 0.30].enumerated() {
            NSBezierPath(
                roundedRect: NSRect(
                    x: bounds.minX + (0.27 + CGFloat(index) * 0.16) * bounds.width,
                    y: bounds.minY + (0.56 - height / 2) * bounds.height,
                    width: bounds.width * 0.065, height: bounds.height * height),
                xRadius: bounds.width * 0.033, yRadius: bounds.width * 0.033
            ).fill()
        }
    }

    static let template: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            draw(in: rect.insetBy(dx: 1, dy: 1), color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "轻语"
        return image
    }()
}
