import AppKit
import Foundation

let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let bounds = NSRect(x: 20, y: 20, width: 984, height: 984)
let path = NSBezierPath(roundedRect: bounds, xRadius: 220, yRadius: 220)
NSColor(calibratedRed: 0.15, green: 0.48, blue: 0.39, alpha: 1).setFill()
path.fill()
let inner = NSBezierPath(
    roundedRect: NSRect(x: 45, y: 45, width: 934, height: 934), xRadius: 204, yRadius: 204)
NSGradient(
    starting: NSColor(calibratedRed: 0.30, green: 0.66, blue: 0.54, alpha: 1),
    ending: NSColor(calibratedRed: 0.11, green: 0.37, blue: 0.31, alpha: 1))!.draw(
        in: inner, angle: 285)
let bars: [CGFloat] = [120, 255, 390, 300, 150]
NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
for (i, height) in bars.enumerated() {
    let x = CGFloat(310 + i * 88)
    let bar = NSBezierPath(
        roundedRect: NSRect(x: x, y: (1024 - height) / 2, width: 55, height: height), xRadius: 27,
        yRadius: 27)
    bar.fill()
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
