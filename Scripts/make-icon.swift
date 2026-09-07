import AppKit

let size = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1) }
let accent = color(29, 155, 240)
func rounded(_ rect: NSRect, _ radius: CGFloat, _ fill: NSColor) {
    fill.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
color(0, 5, 15).setFill(); NSRect(origin: .zero, size: size).fill()
rounded(NSRect(x: 166, y: 182, width: 692, height: 646), 100, accent)
rounded(NSRect(x: 182, y: 198, width: 660, height: 490), 82, color(9, 13, 53))
for x in [338, 686] { rounded(NSRect(x: x - 22, y: 759, width: 44, height: 120), 22, color(220, 231, 255)) }
for (x, y) in [(305, 544), (510, 544), (715, 544), (305, 414), (305, 284)] {
    color(146, 156, 175).setFill(); NSBezierPath(ovalIn: NSRect(x: x - 24, y: y - 24, width: 48, height: 48)).fill()
}
accent.setFill()
NSBezierPath(ovalIn: NSRect(x: 420, y: 274, width: 324, height: 190)).fill()
let tail = NSBezierPath(); tail.move(to: NSPoint(x: 705, y: 382)); tail.line(to: NSPoint(x: 795, y: 492)); tail.line(to: NSPoint(x: 800, y: 348)); tail.line(to: NSPoint(x: 730, y: 308)); tail.close(); tail.fill()
color(0, 5, 15).setFill(); NSBezierPath(ovalIn: NSRect(x: 466, y: 402, width: 20, height: 20)).fill()
NSGraphicsContext.restoreGraphicsState()
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("WhaleCal/Resources/Assets.xcassets")
try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("AppIcon.appiconset/AppIcon.png"))
try "{\"info\":{\"author\":\"xcode\",\"version\":1}}".write(to: root.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try "{\"images\":[{\"filename\":\"AppIcon.png\",\"idiom\":\"universal\",\"platform\":\"ios\",\"size\":\"1024x1024\"}],\"info\":{\"author\":\"xcode\",\"version\":1}}".write(to: root.appendingPathComponent("AppIcon.appiconset/Contents.json"), atomically: true, encoding: .utf8)
