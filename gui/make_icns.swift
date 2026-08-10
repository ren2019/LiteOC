import Foundation

let representations: [(String, String)] = [
    ("icp4", "AppIcon.iconset/icon_16x16.png"),
    ("ic11", "AppIcon.iconset/icon_16x16@2x.png"),
    ("icp5", "AppIcon.iconset/icon_32x32.png"),
    ("ic12", "AppIcon.iconset/icon_32x32@2x.png"),
    ("ic07", "AppIcon.iconset/icon_128x128.png"),
    ("ic13", "AppIcon.iconset/icon_128x128@2x.png"),
    ("ic08", "AppIcon.iconset/icon_256x256.png"),
    ("ic14", "AppIcon.iconset/icon_256x256@2x.png"),
    ("ic09", "AppIcon.iconset/icon_512x512.png"),
    ("ic10", "AppIcon.iconset/icon_512x512@2x.png")
]

func appendUInt32(_ value: Int, to data: inout Data) {
    var bigEndian = UInt32(value).bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

var chunks = Data()
for (type, path) in representations {
    let png = try Data(contentsOf: URL(fileURLWithPath: path))
    chunks.append(type.data(using: .ascii)!)
    appendUInt32(png.count + 8, to: &chunks)
    chunks.append(png)
}

var icon = Data("icns".utf8)
appendUInt32(chunks.count + 8, to: &icon)
icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: "AppIcon.icns"), options: .atomic)
print("wrote AppIcon.icns (Swift compatibility path)")
