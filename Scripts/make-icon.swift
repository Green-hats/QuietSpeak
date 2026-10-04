import AppKit
import Foundation

@main struct IconGenerator {
    static func main() throws {
        let size = 1024
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor(srgbRed: 2.0 / 255.0, green: 168.0 / 255.0, blue: 111.0 / 255.0, alpha: 1)
            .setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944),
            xRadius: 210, yRadius: 210
        ).fill()
        QuietSpeakIcon.draw(in: NSRect(x: 254, y: 240, width: 516, height: 516), color: .white)
        NSGraphicsContext.restoreGraphicsState()
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
