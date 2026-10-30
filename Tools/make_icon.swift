import AppKit

// Renders the application icon (1024×1024 PNG) – usage: make_icon <out.png>

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// rounded square background with a blue gradient
let inset: CGFloat = 90
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let path = CGPath(roundedRect: rect, cornerWidth: 190, cornerHeight: 190, transform: nil)
ctx.addPath(path)
ctx.clip()
let colors = [NSColor(calibratedRed: 0.05, green: 0.25, blue: 0.62, alpha: 1).cgColor,
              NSColor(calibratedRed: 0.10, green: 0.55, blue: 0.95, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: inset), end: CGPoint(x: 0, y: size - inset), options: [])
ctx.resetClip()

// lightning bolt
let bolt = NSBezierPath()
bolt.move(to: NSPoint(x: 560, y: 860))
bolt.line(to: NSPoint(x: 330, y: 470))
bolt.line(to: NSPoint(x: 500, y: 470))
bolt.line(to: NSPoint(x: 430, y: 170))
bolt.line(to: NSPoint(x: 700, y: 580))
bolt.line(to: NSPoint(x: 525, y: 580))
bolt.close()
NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.15, alpha: 1).setFill()
bolt.fill()
NSColor(calibratedWhite: 0.1, alpha: 0.35).setStroke()
bolt.lineWidth = 10
bolt.stroke()

// caption
let style = NSMutableParagraphStyle()
style.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 132, weight: .heavy),
    .foregroundColor: NSColor.white,
    .paragraphStyle: style,
]
NSString(string: "BLHeli").draw(in: NSRect(x: 0, y: 150, width: size, height: 170), withAttributes: attrs)
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
