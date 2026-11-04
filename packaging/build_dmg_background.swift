import AppKit

let width: CGFloat = 660
let height: CGFloat = 400
let scale: CGFloat = 2.0

let size = NSSize(width: width, height: height)
let image = NSImage(size: size)

image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("Failed to get CGContext")
}

// 1. Base dark background (#0f0f12)
let bgRect = CGRect(x: 0, y: 0, width: width, height: height)
ctx.setFillColor(CGColor(red: 15/255.0, green: 15/255.0, blue: 18/255.0, alpha: 1.0))
ctx.fill(bgRect)

// 2. Subtle decorative card contour
let cardRect = CGRect(x: 24, y: 24, width: width - 48, height: height - 48)
let cardPath = CGPath(roundedRect: cardRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
ctx.setStrokeColor(CGColor(red: 255/255.0, green: 255/255.0, blue: 255/255.0, alpha: 0.08))
ctx.setLineWidth(1)
ctx.addPath(cardPath)
ctx.strokePath()

// 3. Subtle target pedestals for Left Icon (Frames.app at 170, 200) and Right Icon (Applications at 490, 200)
// Note: In AppKit coordinate system, (0,0) is bottom-left. Finder places icons at (x, y) measured from top-left.
// For Finder window of height 400:
// Top-left y=190 in Finder corresponds to y = 400 - 190 = 210 in AppKit.
let leftTargetCenter = CGPoint(x: 175, y: 200)
let rightTargetCenter = CGPoint(x: 485, y: 200)

for center in [leftTargetCenter, rightTargetCenter] {
    let pedestalRect = CGRect(x: center.x - 70, y: center.y - 70, width: 140, height: 140)
    let pPath = CGPath(roundedRect: pedestalRect, cornerWidth: 24, cornerHeight: 24, transform: nil)
    ctx.setFillColor(CGColor(red: 255/255.0, green: 255/255.0, blue: 255/255.0, alpha: 0.025))
    ctx.fill(pedestalRect)
    ctx.setStrokeColor(CGColor(red: 255/255.0, green: 255/255.0, blue: 255/255.0, alpha: 0.06))
    ctx.setLineWidth(1)
    ctx.addPath(pPath)
    ctx.strokePath()
}

// 4. Elegant connecting directional arrow between pedestals
let arrowPath = CGMutablePath()
let startPt = CGPoint(x: leftTargetCenter.x + 80, y: leftTargetCenter.y)
let endPt = CGPoint(x: rightTargetCenter.x - 80, y: rightTargetCenter.y)
arrowPath.move(to: startPt)
arrowPath.addLine(to: CGPoint(x: endPt.x - 12, y: endPt.y))

ctx.setStrokeColor(CGColor(red: 249/255.0, green: 115/255.0, blue: 22/255.0, alpha: 0.65)) // terracotta / warm orange
ctx.setLineWidth(2.5)
ctx.setLineCap(.round)
ctx.addPath(arrowPath)
ctx.strokePath()

// Arrow head
let headPath = CGMutablePath()
headPath.move(to: CGPoint(x: endPt.x - 16, y: endPt.y + 7))
headPath.addLine(to: endPt)
headPath.addLine(to: CGPoint(x: endPt.x - 16, y: endPt.y - 7))
ctx.setStrokeColor(CGColor(red: 249/255.0, green: 115/255.0, blue: 22/255.0, alpha: 0.85))
ctx.setLineWidth(2.5)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.addPath(headPath)
ctx.strokePath()

// 5. Typography
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center

let titleFont = NSFont.systemFont(ofSize: 18, weight: .semibold)
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor(white: 0.94, alpha: 1.0),
    .paragraphStyle: paragraphStyle
]

let titleText = "Drag Frames to Applications to install"
let titleRect = CGRect(x: 40, y: 320, width: width - 80, height: 28)
(titleText as NSString).draw(in: titleRect, withAttributes: titleAttrs)

let subFont = NSFont.systemFont(ofSize: 12, weight: .regular)
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: subFont,
    .foregroundColor: NSColor(white: 0.55, alpha: 1.0),
    .paragraphStyle: paragraphStyle
]
let subText = "Optimized natively for Apple Silicon (ARM64)"
let subRect = CGRect(x: 40, y: 298, width: width - 80, height: 20)
(subText as NSString).draw(in: subRect, withAttributes: subAttrs)

// Bottom instructions
let footerAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 11, weight: .regular),
    .foregroundColor: NSColor(white: 0.40, alpha: 1.0),
    .paragraphStyle: paragraphStyle
]
let footerText = "Once dragged, open Applications and launch Frames"
let footerRect = CGRect(x: 40, y: 46, width: width - 80, height: 18)
(footerText as NSString).draw(in: footerRect, withAttributes: footerAttrs)

image.unlockFocus()

// Save at 1x and 2x
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width * scale),
    pixelsHigh: Int(height * scale),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: CGRect(origin: .zero, size: size))
NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to convert image to PNG")
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
let outputURL = URL(fileURLWithPath: outputPath)
try pngData.write(to: outputURL)
print("DMG background rendered successfully to: \(outputPath)")
