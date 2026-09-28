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
        logLine("❌ 无法读取当前显示模式")
        return false
    }
    // 只捕获目标参数，不持有模式对象——真唤醒后显示器重新枚举，旧对象会静默失效
    let targetW = current.width, targetH = current.height, targetHz = current.refreshRate
    logLine("当前模式: \(targetW)x\(targetH) @ \(Int(targetHz))Hz")

    let fallback = findMode(id: id, w: FALLBACK_W, h: FALLBACK_H, hz: 60)
        ?? displayModes(for: id).last { $0.width != targetW }

    guard let alt = fallback, alt.width != targetW || alt.height != targetH else {
        logLine("❌ 没有可切换的备用分辨率模式")
        return false
    }

    applyMode(alt, id: id)
    logLine("已切到 \(alt.width)x\(alt.height)，等待信号重建…")
    usleep(1_200_000)

    // 切回：按参数重新查找模式（不信任切下前捕获的对象），并验证重试
    for attempt in 1...4 {
        guard let back = findMode(id: id, w: targetW, h: targetH, hz: targetHz)
            ?? displayModes(for: id).first(where: { $0.width == targetW && $0.height == targetH }) else {
            logLine("❌ 找不回目标模式 \(targetW)x\(targetH)")
            return false
        }
        applyMode(back, id: id)
        usleep(900_000)
        if let now = CGDisplayCopyDisplayMode(id), now.width == targetW && now.height == targetH {
            logLine("✅ 已切回 \(targetW)x\(targetH) @ \(Int(targetHz))Hz\(attempt > 1 ? "（第 \(attempt) 次尝试成功）" : "")")
            return true
        }
        logLine("⚠️ 切回未生效（第 \(attempt) 次），重试…")
    }
    logLine("❌ 重同步失败 (mode now: \(currentModeString()))")
    return false
}

// restore：优先恢复持久化的最后已知模式，否则选面积最大、刷新率最接近 60Hz 的
var statePath: String { NSHomeDirectory() + "/.workbuddy/run/display-lastmode.txt" }

func saveCurrentMode() {
    try? currentModeString().write(toFile: statePath, atomically: true, encoding: .utf8)
}

func restoreNative(_ arg: String?) -> Bool {
    let id = CGMainDisplayID()
    var target: CGDisplayMode?

    // 1) 显式参数 WxH@Hz
    if let a = arg, let m = a.firstIndex(of: "x") {
        let w = Int(a[..<m]), rest = a[a.index(after: m)...]
        let hzParts = rest.split(separator: "@")
        let h = Int(hzParts[0])
        let hz = hzParts.count > 1 ? Double(hzParts[1]) : 60
        if let w = w, let h = h {
            target = findMode(id: id, w: w, h: h, hz: hz ?? 60)
                ?? displayModes(for: id).first { $0.width == w && $0.height == h }
        }
    }
    // 2) 持久化的最后已知模式
    if target == nil, let saved = try? String(contentsOfFile: statePath, encoding: .utf8) {
        let parts = saved.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "x").flatMap { $0.split(separator: "@") }
        if parts.count >= 2, let w = Int(parts[0]), let h = Int(parts[1]) {
            let hz = parts.count > 2 ? Double(parts[2]) ?? 60 : 60
            target = findMode(id: id, w: w, h: h, hz: hz)
                ?? displayModes(for: id).first { $0.width == w && $0.height == h }
        }
    }
    // 3) 兜底：面积最大、刷新率最接近 60Hz（低刷新=低带宽，避开虚线诱因）
    if target == nil {
        let modes = displayModes(for: id)
        if let maxArea = modes.map({ $0.width * $0.height }).max() {
            target = modes.filter { $0.width * $0.height == maxArea }
                .min { abs($0.refreshRate - 60) < abs($1.refreshRate - 60) }
        }
    }

    guard let best = target else {
        logLine("❌ restore: 无可用模式")
        return false
    }
    applyMode(best, id: id)
    usleep(1_000_000)
    let ok = CGDisplayCopyDisplayMode(id).map { $0.width == best.width && $0.height == best.height } ?? false
    logLine("\(ok ? "✅" : "❌") restore → \(best.width)x\(best.height) @ \(Int(best.refreshRate))Hz (mode now: \(currentModeString()))")
    if ok { saveCurrentMode() }
    return ok
}

func logLine(_ s: String) {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "[\(df.string(from: Date()))] \(s)\n"
    print(line, terminator: "")
    let path = NSHomeDirectory() + "/.workbuddy/logs/display-resync.log"
    if FileManager.default.fileExists(atPath: path) == false {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    }
}

func currentModeString() -> String {
    if let m = CGDisplayCopyDisplayMode(CGMainDisplayID()) {
        return "\(m.width)x\(m.height)@\(Int(m.refreshRate))Hz"
    }
    return "no-display"
}

final class WakeWatcher {
    static var pidPath: String { NSHomeDirectory() + "/.workbuddy/run/display-resync-watch.pid" }

    // 单实例守卫：已有守护存活则直接退出（防 LaunchAgent/zshrc/手动多入口并存互切分辨率）
    static func guardSingleInstance() -> Bool {
        let fm = FileManager.default
        if let data = fm.contents(atPath: pidPath),
           let str = String(data: data, encoding: .utf8),
           let old = Int32(str.trimmingCharacters(in: .whitespacesAndNewlines)),
           old != ProcessInfo.processInfo.processIdentifier,
           kill(old, 0) == 0 {
            logLine("⚠️ 已有守护在运行 (pid \(old))，本次启动退出")
            return false
        }
        try? fm.createDirectory(atPath: (pidPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? "\(ProcessInfo.processInfo.processIdentifier)".write(toFile: pidPath, atomically: true, encoding: .utf8)
        return true
    }

    static func start() {
        guard guardSingleInstance() else { exit(0) }
        logLine("👀 watcher started (pid \(ProcessInfo.processInfo.processIdentifier)), mode=\(currentModeString())")
        saveCurrentMode()
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
                let before = currentModeString()
                logLine("🌙 系统唤醒 detected (mode before: \(before))，执行重同步…")
                let ok = resyncOnce()
                if ok { saveCurrentMode() }
                logLine(ok ? "✅ 重同步完成 (mode now: \(currentModeString()))"
                           : "❌ 重同步失败 (mode now: \(currentModeString()))")
            }
        }
        CFRunLoopRun()
    }
}

let args = CommandLine.arguments

if args.contains("--watch") {
    WakeWatcher.start()
} else if args.contains("--restore") {
    let arg = args.drop(while: { $0 != "--restore" }).dropFirst().first
    exit(restoreNative(arg) ? 0 : 1)
} else if args.contains("--status") {
    let id = CGMainDisplayID()
    if let m = CGDisplayCopyDisplayMode(id) {
        let scaled = m.pixelWidth != m.width ? "（HiDPI 缩放）" : "（原生）"
        print("\(m.width)x\(m.height) @ \(Int(m.refreshRate))Hz \(scaled)")
    }
} else {
    exit(resyncOnce() ? 0 : 1)
}
