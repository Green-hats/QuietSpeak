import AppKit
import Foundation

@main struct IconGenerator {
    static func main() throws {
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        image.lockFocus()
        NSColor(calibratedRed: 0.16, green: 0.39, blue: 0.30, alpha: 1).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944),
            xRadius: 210, yRadius: 210
        ).fill()
        QuietSpeakIcon.draw(in: NSRect(x: 254, y: 240, width: 516, height: 516), color: .white)
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
