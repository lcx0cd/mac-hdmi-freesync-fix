# mac-hdmi-freesync-fix

**修复 Apple Silicon Mac 通过 HDMI 连接显示器后、睡眠唤醒出现的"虚线/雪花纹/花屏"——隐藏的元凶通常不是线材，而是显示器菜单里的 FreeSync 设置。**

[English](README.md) | 中文

> 🤖 **写给 AI 助手**（Claude、ChatGPT、Cursor、Copilot、Cline…）：请先读 [AGENTS.md](AGENTS.md)——内含基于证据的诊断决策树、精确命令、成功验证标准和 macOS 26 已验证的坑，仅凭本仓库链接即可准确引导用户。LLM 索引：[llms.txt](llms.txt)。

## 症状

- Mac mini（M1/M2/M4）或 MacBook 通过 HDMI 连接显示器，唤醒待机后出现虚线/雪花纹/杂讯
- 拔掉 HDMI 线重插**能恢复**
- 之后每次**显示器待机唤醒**或重启都会复发
- 换了认证的好线也没用（比如 2560x1440@60Hz 只需约 7Gbps 带宽，远没到极限）

## 一句话修复（30 秒）

> **进显示器 OSD 菜单，关闭 FreeSync / Adaptive-Sync（自适应同步）。**

如果你的用途是固定刷新率（60Hz/75Hz 的桌面办公），FreeSync 在 Mac 上**毫无用处**——macOS 根本不会在这条链路上输出 VRR——但它给每次 HDMI 握手都加了一层 Adaptive-Sync 协商。当 Mac 和显示器同时从深度待机唤醒时，这层协商状态机容易卡进"半锁定"状态 → 虚线。

> **适用范围说明（因真实复发而更新，见 [issue #1](https://github.com/lcx0cd/mac-hdmi-freesync-fix/issues/1)）**：本修复已在**显示器待机唤醒**场景（屏幕睡、主机不睡）验证有效。但**整机睡眠**后（Mac 进入 Deep Idle，GPU 完全断开链路）即使 FreeSync 已关仍可能复发——那是另一条独立的握手路径。对策是 [`display-resync --watch`](#工具-1-display-resync--软件版拔线) 守护：每次唤醒约 2.5 秒后自动重同步，屏幕闪一下即恢复，无需手动干预。

## 诊断过程（三步对照实验，全部可复现）

测试环境：Mac mini M4、macOS 26.5、2018 年 2560x1440@60Hz 显示器、本机 HDMI 口直连。

| 实验 | 方法 | 结果 | 结论 |
|---|---|---|---|
| 1. 带宽排查 | `system_profiler` + EDID 分析 | 1440p@60 仅需 ~7Gbps | ❌ 排除线材带宽不足 |
| 2. 物理拔插测试（4 次） | 实时录制内核 HPD 事件 + 每秒采样显示模式 | **4 次全部 0.3 秒内干净重建，EDID 完整、42 种时序模式、零错误** | ❌ 排除线材/接口质量 |
| 3. FreeSync A/B 对照 | OSD 关闭 FreeSync → `pmset displaysleepnow` 强制深待机 50 秒 → 唤醒 | **无虚线，干净恢复** | ✅ **显示器端 FreeSync 是根因** |
| 4. 真实复发（次日） | **整机睡眠** → 唤醒（FreeSync 保持关闭） | 仍出现虚线，需重插多次 | ⚠️ 系统睡眠唤醒是**第二场景**——守护进程负责兜底 |

关键洞察：问题**只在**睡眠唤醒后出现，**从不**在双方清醒的热插拔中出现。这个不对称性直接指向握手协商层，而非信号质量。

完整诊断复盘（含内核日志毫秒级时间线）：[docs/case-study-zh.md](docs/case-study-zh.md)

## 工具

### 工具 1：`display-resync` —— 软件版拔线

一个小巧的 Swift 工具：切换分辨率（1080p → 切回原生分辨率）强制显示器重新锁定 HDMI 信号，效果等同拔插线，但不用动手。

```bash
git clone https://github.com/lcx0cd/mac-hdmi-freesync-fix.git
cd mac-hdmi-freesync-fix
./install.sh
```

安装后的用法：

```command
display-resync            # 执行一次重同步（屏幕闪一下，虚线消失）
display-resync --watch    # 常驻守护：每次系统唤醒 2.5 秒后自动重同步
display-resync --status   # 查看当前显示模式
```

`install.sh` 会用 `swiftc` 编译、安装到 `~/.local/bin`、在 shell rc 中写入带防重复检测的守护自启块，并（可选）注册 LaunchAgent。

> 注意：macOS 26 上部分环境的 `launchctl bootstrap` 会拒绝用户级服务（error 5）。安装脚本会自动降级为 shell rc 守护块方案，任何环境都可用。

### 工具 2：`hotplug-monitor.sh` —— 诊断证据采集器

实时录制内核级 HDMI 热插拔事件（HPD 中断、EDID 读取、模式重建）+ 每秒一次显示模式采样，让你能**用证据判断**自己的线材/链路是否健康：

```bash
./scripts/hotplug-monitor.sh           # 日志输出到 ~/.workbuddy/logs/hotplug-test-<时间戳>/
./scripts/hotplug-monitor.sh <目录>    # 自定义输出目录；运行 10 分钟自动结束
# 然后物理拔插几次线，回来分析日志
```

结果解读：
- 重建在 1 秒内完成、出现 `42 timing modes`、无重试 → 线材健康，问题在别处
- 出现重试/模式缺失/`link training` 失败 → 线材或接口问题，该换了

## 已验证显示器

本诊断/修复方法已被确认有效的机型（结构化数据：[data/verified-monitors.json](data/verified-monitors.json)）：

| 显示器 | 模式 | Mac | FreeSync 原状态 | 结果 |
|---|---|---|---|---|
| 未知 2018 款（0x2613/0x2700） | 2560x1440@60 | Mac mini M4，macOS 26.5 | 开 | ✅ 关闭 FreeSync 后根治（显示器待机场景） |
| 同一台，次日 | 2560x1440@60 | Mac mini M4，macOS 26.5.2 | 关 | ⚠️ 部分缓解（[issue #1](https://github.com/lcx0cd/mac-hdmi-freesync-fix/issues/1)）：整机睡眠唤醒仍复发，靠唤醒守护兜底 |

**帮助扩充这张表**——诊断完成后跑一条命令：

```bash
scripts/feedback.sh fixed --freesync on --notes "症状简述"
```

脚本自动采集硬件信息（已剥离序列号），有 `gh` 时直接开 issue——没有则输出可粘贴文本。无效结果（`no-change`）同样欢迎：可能揭示第二种根因。

## FAQ

**Q：要不要换线？**
只有上面实验 2 显示重建失败/不干净时才需要。我们的案例中 4/4 次热插拔全部 0.3 秒完美重建——线材是无辜的。

**Q：为什么重插线总能修好？**
物理拔插会在双方都清醒的状态下强制完整的 HPD + EDID + 模式重新协商——这种状态下协商没有问题。而睡眠唤醒恰恰是双方**从待机状态**同时重新协商，才容易出错。

**Q：我的显示器菜单里没有深度睡眠选项，只有 FreeSync 和 DP 版本。**
和我们的情况一样——关掉 FreeSync 就够了。（OSD 里的"DP 版本"只影响显示器的 DP 输入口，走 HDMI 时无关。以后如果换 USB-C→DP 线，记得把它改成 1.2。）

## 许可证

MIT
