import Cocoa
import CoreGraphics

let S = 1024

// 1) 白色 globe: SF Symbol "globe" 的 alpha 当 mask, 填白色
let cfg = NSImage.SymbolConfiguration(pointSize: 620, weight: .regular)
let base = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!
    .withSymbolConfiguration(cfg)!
let white = NSImage(size: base.size)
white.lockFocus()
let ctx0 = NSGraphicsContext.current!.cgContext
let r0 = CGRect(origin: .zero, size: base.size)
if let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    ctx0.clip(to: r0, mask: cg)
    ctx0.setFillColor(NSColor.white.cgColor)
    ctx0.fill(r0)
}
white.unlockFocus()

// 2) 画布: 蓝色圆角渐变 + 白色 globe 居中
let canvas = NSImage(size: NSSize(width: S, height: S))
canvas.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S),
                   cornerWidth: 228, cornerHeight: 228, transform: nil))
ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [NSColor(srgbRed: 0x3B/255, green: 0x82/255, blue: 0xF6/255, alpha: 1).cgColor,  // #3B82F6
             NSColor(srgbRed: 0x1E/255, green: 0x40/255, blue: 0xAF/255, alpha: 1).cgColor] as CFArray,  // #1E40AF
    locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
let sz = white.size
white.draw(in: NSRect(x: CGFloat(S)/2 - sz.width/2, y: CGFloat(S)/2 - sz.height/2,
                      width: sz.width, height: sz.height),
           from: .zero, operation: .sourceOver, fraction: 1)
canvas.unlockFocus()

// 3) 存 PNG
let png = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
    .representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: "icon_1024.png"))
print("wrote icon_1024.png (globe)")
