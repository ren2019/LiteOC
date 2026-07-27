import Cocoa
import CoreGraphics

// 渲染菜单栏小图标: 圆角方块 + 白色 globe, 彩色/灰色 两个版本
func renderTile(bgTop: NSColor, bgBottom: NSColor, _ S: CGFloat, _ outFile: String) {
    // 白色 globe (SF Symbol 模板 alpha 当 mask)
    let cfg = NSImage.SymbolConfiguration(pointSize: S * 0.60, weight: .regular)
    let base = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!
        .withSymbolConfiguration(cfg)!
    let white = NSImage(size: base.size)
    white.lockFocus()
    let cw = NSGraphicsContext.current!.cgContext
    let rw = CGRect(origin: .zero, size: base.size)
    if let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        cw.clip(to: rw, mask: cg)
        cw.setFillColor(NSColor.white.cgColor); cw.fill(rw)
    }
    white.unlockFocus()

    let canvas = NSImage(size: NSSize(width: S, height: S))
    canvas.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let cr = S * 0.22
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S),
                       cornerWidth: cr, cornerHeight: cr, transform: nil))
    ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [bgTop.cgColor, bgBottom.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
    let sz = white.size
    white.draw(in: NSRect(x: S/2 - sz.width/2, y: S/2 - sz.height/2, width: sz.width, height: sz.height),
               from: .zero, operation: .sourceOver, fraction: 1)
    canvas.unlockFocus()

    let png = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
        .representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: outFile))
}

renderTile(bgTop: NSColor(srgbRed: 0x3B/255, green: 0x82/255, blue: 0xF6/255, alpha: 1),   // 蓝
           bgBottom: NSColor(srgbRed: 0x1E/255, green: 0x40/255, blue: 0xAF/255, alpha: 1),
           64, "menubar_color.png")
renderTile(bgTop: NSColor(srgbRed: 0x9C/255, green: 0xA3/255, blue: 0xAF/255, alpha: 1),   // 灰
           bgBottom: NSColor(srgbRed: 0x6B/255, green: 0x72/255, blue: 0x80/255, alpha: 1),
           64, "menubar_gray.png")
print("wrote menubar_color.png + menubar_gray.png")
