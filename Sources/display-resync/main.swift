// display-resync — Mac mini HDMI 软重插工具
// 用法:
//   display-resync          执行一次信号重同步（切 1080p -> 切回原分辨率）
//   display-resync --watch  常驻监听系统唤醒，唤醒后自动重同步
//   display-resync --status 显示当前显示模式

import CoreGraphics
import AppKit
import Foundation

let FALLBACK_W = 1920
let FALLBACK_H = 1080

func displayModes(for id: CGDirectDisplayID) -> [CGDisplayMode] {
    guard let modes = CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode] else { return [] }
    return modes
}

func findMode(id: CGDirectDisplayID, w: Int, h: Int, hz: Double) -> CGDisplayMode? {
    displayModes(for: id).first { $0.width == w && $0.height == h && abs($0.refreshRate - hz) < 1 }
}

func applyMode(_ mode: CGDisplayMode, id: CGDirectDisplayID) {
    var cfg: CGDisplayConfigRef?
    CGBeginDisplayConfiguration(&cfg)
    CGConfigureDisplayWithDisplayMode(cfg, id, mode, nil)
    CGCompleteDisplayConfiguration(cfg, .permanently)
}

func resyncOnce() -> Bool {
    let id = CGMainDisplayID()
    guard let current = CGDisplayCopyDisplayMode(id) else {
        print("❌ 无法读取当前显示模式")
        return false
    }
    print("当前模式: \(current.width)x\(current.height) @ \(Int(current.refreshRate))Hz")

    let fallback = findMode(id: id, w: FALLBACK_W, h: FALLBACK_H, hz: 60)
        ?? displayModes(for: id).last { $0.width != current.width }

    guard let alt = fallback, alt != current else {
        print("❌ 没有可切换的备用分辨率模式")
        return false
    }

    applyMode(alt, id: id)
    print("已切到 \(alt.width)x\(alt.height)，等待信号重建…")
    usleep(1_200_000)
    applyMode(current, id: id)
    usleep(500_000)
    print("✅ 已切回 \(current.width)x\(current.height) @ \(Int(current.refreshRate))Hz — 显示器已重新锁定信号")
    return true
}

final class WakeWatcher {
    static func start() {
        print("👀 监听中：每次系统唤醒后 2.5 秒自动重同步显示信号（Ctrl+C 退出）")
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
                print("🌙 检测到系统唤醒，执行显示重同步…")
                _ = resyncOnce()
            }
        }
        CFRunLoopRun()
    }
}

let args = CommandLine.arguments

if args.contains("--watch") {
    WakeWatcher.start()
} else if args.contains("--status") {
    let id = CGMainDisplayID()
    if let m = CGDisplayCopyDisplayMode(id) {
        let scaled = m.pixelWidth != m.width ? "（HiDPI 缩放）" : "（原生）"
        print("\(m.width)x\(m.height) @ \(Int(m.refreshRate))Hz \(scaled)")
    }
} else {
    exit(resyncOnce() ? 0 : 1)
}
