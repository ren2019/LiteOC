import Cocoa
import CoreGraphics

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex>>16)&0xff)/255,
            green: CGFloat((hex>>8)&0xff)/255,
            blue: CGFloat(hex&0xff)/255, alpha: 1)
}

func savePNG(_ img: NSImage, _ outFile: String) {
    let png = NSBitmapImageRep(data: img.tiffRepresentation!)!
        .representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: outFile))
}

// 透明底 + 单色 SF Symbol (盾), 运行时 isTemplate=true 随菜单栏明暗自适应
func renderSymbol(_ name: String, _ hex: UInt32, _ S: CGFloat, _ outFile: String) {
    let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: S * 0.80, weight: .regular))!
    let canvas = NSImage(size: NSSize(width: S, height: S))
    canvas.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let bs = base.size, dx = (S - bs.width) / 2, dy = (S - bs.height) / 2
    if let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.clip(to: CGRect(x: dx, y: dy, width: bs.width, height: bs.height), mask: cg)
        ctx.setFillColor(color(hex).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    }
    canvas.unlockFocus()
    savePNG(canvas, outFile)
}

// 透明底 + 实心单色圆 (状态灯, 无光晕)
func renderDot(_ hex: UInt32, _ S: CGFloat, _ outFile: String) {
    let canvas = NSImage(size: NSSize(width: S, height: S))
    canvas.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let r = S * 0.42
    ctx.setFillColor(color(hex).cgColor)
    ctx.fillEllipse(in: CGRect(x: S/2 - r, y: S/2 - r, width: 2*r, height: 2*r))
    canvas.unlockFocus()
    savePNG(canvas, outFile)
}

renderSymbol("lock.shield", 0xFFFFFF, 64, "menubar_gray.png")   // 未连接: 盾 (template)
renderDot(0x22C55E, 64, "menubar_color.png")                    // 已连接: 绿灯
renderDot(0xEF4444, 64, "menubar_red.png")                      // 异常: 红灯
renderDot(0xF59E0B, 64, "menubar_yellow.png")                   // 重连中: 黄灯 (闪烁)
print("wrote menubar_gray (shield) + menubar_color (green) + menubar_red (red) + menubar_yellow (amber)")
