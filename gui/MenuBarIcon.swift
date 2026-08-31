import Foundation

// 菜单栏九宫格点阵图标:纯逻辑模型 (无 AppKit 依赖,风格对齐 MenuPresentation)。
// 点索引 0-8 按行优先: 0 1 2 / 3 4 5 / 6 7 8。

enum MenuBarIconGeometry {
    static let canvas: CGFloat = 18          // 菜单栏图标边长 (pt)
    static let dotRadius: CGFloat = 1.8      // 几何法则: 画布 10r = 圆心间距 3r + 外边距 1r + 半径
    static let dimAlpha: CGFloat = 0.22      // 灭点: 同色 22% 不透明度 (始终画出)
}

struct IconSpec: Equatable {
    /// 循环播放的帧序列;每帧是亮点索引集合 (升序)。单帧即静态。
    let frames: [[Int]]
    /// 帧间隔 (秒);静态图标为 0。
    let frameInterval: TimeInterval
    /// 错误态: 红色 (systemRed) 非 template;否则 template 单色跟随系统亮暗。
    let isErrorRed: Bool

    var isAnimated: Bool { frames.count > 1 }
}

private let brandT: [Int] = [0, 3, 4, 5, 6]              // 品牌图案: 横 T ⊢ (第一列 + 第二行)
private let chaseRing: [Int] = [0, 1, 2, 5, 8, 7, 6, 3]  // connecting 外圈顺时针环序

private func staticSpec(_ lit: [Int], isErrorRed: Bool = false) -> IconSpec {
    IconSpec(frames: [lit.sorted()], frameInterval: 0, isErrorRed: isErrorRed)
}

func iconSpec(for state: TunnelState, isConfigured: Bool) -> IconSpec {
    // disconnected 无论配置与否都是全灭, isConfigured 不改变图标 (spec 决策)。
    switch state {
    case .disconnected:
        return staticSpec([])
    case .connected:
        return staticSpec(brandT)
    case .connecting:
        // 外圈顺时针追逐: 头点 + 2 个拖尾点亮, 共 8 帧。
        let frames = (0..<chaseRing.count).map { head in
            [0, 1, 2].map { chaseRing[(head - $0 + chaseRing.count) % chaseRing.count] }.sorted()
        }
        return IconSpec(frames: frames, frameInterval: 0.3, isErrorRed: false)
    case .disconnecting:
        // T 的坍缩: 按 [5,4,0,6,3] 逐点熄灭, 共 6 帧 (末帧全灭)。
        var remaining = Set(brandT)
        var frames: [[Int]] = [brandT]
        for dot in [5, 4, 0, 6, 3] {
            remaining.remove(dot)
            frames.append(remaining.sorted())
        }
        return IconSpec(frames: frames, frameInterval: 0.4, isErrorRed: false)
    case .reconnecting:
        return IconSpec(frames: [brandT, []], frameInterval: 0.6, isErrorRed: false)
    case .repairing:
        return IconSpec(frames: [[0, 1, 2], [3, 4, 5], [6, 7, 8]], frameInterval: 0.35, isErrorRed: false)
    case .errTimeout:
        return staticSpec([0, 1, 2, 4, 6, 7, 8], isErrorRed: true)      // 沙漏
    case .errDropped:
        return staticSpec([0, 2, 3, 5, 6, 8], isErrorRed: true)         // 断裂双竖
    case .errAuth, .errCert:
        return staticSpec([1, 3, 4, 5, 6, 7, 8], isErrorRed: true)      // 锁
    case .errNetworkChanged, .errReconnectFailed:
        return staticSpec([0, 1, 2, 3, 5, 6, 7, 8], isErrorRed: true)   // 空心环
    case .errRoute, .errStop:
        return staticSpec([0, 2, 4, 6, 8], isErrorRed: true)            // X
    }
}
