import Cocoa
import CoreGraphics

let S: CGFloat = 1024
let U = S / 14                      // 14 单位画布, 1 单位 = 1024/14 pt
let centers: [CGFloat] = [4, 7, 10] // 圆心 4/7/10, 边距均 3, 点阵严格居中
let cMark: Set<Int> = [0, 1, 2, 3, 6, 7, 8] // C 形: 顶行 + 首列 + 底行; [4,5] 灭点

// 1) 画布: 深色 squircle 底板 + 白色 C 形点阵
// 用 NSBitmapImageRep 显式固定像素尺寸, 避免 Retina 屏上 lockFocus 渲染成 2048px
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// 底板: #1d1d1f, 圆角 22.3% * 1024 ≈ 228
ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S),
                   cornerWidth: 228, cornerHeight: 228, transform: nil))
ctx.clip()
ctx.setFillColor(NSColor(srgbRed: 0x1d/255, green: 0x1d/255, blue: 0x1f/255, alpha: 1).cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

// 点阵: 亮 100% / 灭 22%, 点半径 1 单位 (CG y 轴向上, 行号翻转)
for y in 0..<3 { for x in 0..<3 {
    let lit = cMark.contains(y * 3 + x)
    ctx.setFillColor(NSColor.white.withAlphaComponent(lit ? 1 : 0.22).cgColor)
    let cx = centers[x] * U, cy = centers[2 - y] * U
    ctx.fillEllipse(in: CGRect(x: cx - U, y: cy - U, width: 2 * U, height: 2 * U))
}}
NSGraphicsContext.restoreGraphicsState()

// 2) 存 PNG
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: "icon_1024.png"))
print("wrote icon_1024.png (C-shape 3x3 dots, dark squircle)")
