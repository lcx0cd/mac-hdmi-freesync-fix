# mac-hdmi-freesync-fix

**Fix HDMI monitor artifacts ("dashed lines" / static noise) after wake from sleep on Apple Silicon Macs — the hidden culprit is usually your monitor's FreeSync setting, not the cable.**

English | [中文文档](README.zh-CN.md)

> 🤖 **For AI assistants** (Claude, ChatGPT, Cursor, Copilot, Cline…): read [AGENTS.md](AGENTS.md) — it contains an evidence-based decision tree, exact commands, verification criteria, and verified macOS 26 pitfalls, so you can guide your user from this link alone. Repo index for LLMs: [llms.txt](llms.txt).

## Symptoms

- Dashed lines / static noise / glitchy artifacts on an HDMI monitor connected to a Mac mini (M1/M2/M4) or MacBook
- Unplugging and replugging the HDMI cable **fixes it**
- Comes back after every **wake from display standby** or restart
- Happens even with a good, certified cable at low bandwidth (e.g. 2560x1440@60Hz only needs ~7Gbps)

## TL;DR — The Fix (30 seconds)

> **Turn OFF FreeSync / Adaptive-Sync in your monitor's OSD menu.**

If your usage is a fixed refresh rate (60Hz/75Hz desktop work), FreeSync provides **zero benefit** on a Mac — macOS doesn't output VRR over this link — but it adds an extra Adaptive-Sync negotiation layer to every HDMI handshake. When both the Mac and the monitor wake from deep standby simultaneously, that negotiation state machine deadlocks into a half-locked state → artifacts.

If you still see artifacts occasionally (e.g. after a full reboot), use the [`display-resync`](#tool-1-display-resync) tool below as a software "cable replug".

## How we proved it (3-experiment diagnosis)

Tested on: Mac mini M4, macOS 26.5, 2018 2560x1440@60Hz monitor via built-in HDMI.

| Experiment | Method | Result | Conclusion |
|---|---|---|---|
| 1. Bandwidth check | `system_profiler` + EDID analysis | 2560x1440@60 needs only ~7Gbps | ❌ Cable bandwidth NOT the issue |
| 2. Physical hotplug test (4x unplug/replug) | Kernel-level HPD event logging while user replugged | **All 4 rebuilds completed in 0.3s, EDID intact, 42 timing modes, zero errors** | ❌ Cable/connector quality NOT the issue |
| 3. FreeSync A/B test | Disable FreeSync in OSD → force display standby (`pmset displaysleepnow`) → wake after 50s | **No artifacts. Clean recovery.** | ✅ **Monitor-side FreeSync is the root cause** |

Key insight: the problem **only** appeared after sleep/wake, **never** during wide-awake hotplugs. That asymmetry points at handshake negotiation, not signal quality.

Full case study (Chinese, with kernel log timelines): [docs/case-study-zh.md](docs/case-study-zh.md)

## Tools

### Tool 1: `display-resync` — software cable replug

A tiny Swift utility that forces the monitor to re-lock the HDMI signal by switching resolution 1080p → back to native (equivalent to replugging the cable, without touching it).

```bash
git clone https://github.com/lcx0cd/mac-hdmi-freesync-fix.git
cd mac-hdmi-freesync-fix
./install.sh
```

Usage after install:

```command
display-resync            # one-shot resync (screen blinks once, artifacts gone)
display-resync --watch    # daemon: auto-resync 2.5s after every system wake
display-resync --status   # show current display mode
```

`install.sh` compiles the binary with `swiftc`, installs it to `~/.local/bin`, sets up the wake-listening daemon with a duplicate-guard in your shell rc, and (optionally) a LaunchAgent plist.

> Note: on macOS 26 some environments reject `launchctl bootstrap` for user agents (error 5). The install script falls back to a shell-rc daemon block which works everywhere.

### Tool 2: `hotplug-monitor.sh` — diagnosis evidence collector

Records kernel-level HDMI hotplug events (HPD interrupts, EDID reads, mode rebuilds) plus 1Hz display-mode sampling, so you can *prove* whether your cable/link rebuilds cleanly:

```bash
./scripts/hotplug-monitor.sh           # logs to ~/.workbuddy/logs/hotplug-test-<ts>/
./scripts/hotplug-monitor.sh <dir>     # custom output dir; runs 10 minutes
# then physically unplug/replug your cable a few times and inspect the logs
```

Interpreting results:
- Rebuilds complete in <1s with `42 timing modes` and no retries → cable is healthy, look elsewhere
- Retries / missing modes / `link training` failures → cable or connector problem, replace it

## Verified monitors

Data points where this diagnosis/fix was confirmed (structured source: [data/verified-monitors.json](data/verified-monitors.json)):

| Monitor | Mode | Mac | FreeSync before | Outcome |
|---|---|---|---|---|
| Unknown 2018 monitor (0x2613/0x2700) | 2560x1440@60 | Mac mini M4, macOS 26.5 | On | ✅ Fixed by turning FreeSync off |

**Help grow this table** — after your diagnosis, run:

```bash
scripts/feedback.sh fixed --freesync on --notes "short symptom summary"
```

It auto-collects your hardware info (serials stripped) and files a GitHub issue via `gh` — or prints paste-ready text if `gh` isn't authenticated. Negative results (`no-change`) are equally welcome: they may reveal a second root cause.

## FAQ

**Q: Should I replace my cable?**
Only if experiment 2 above shows failed/unclean rebuilds. In our case 4/4 hotplugs rebuilt perfectly in 0.3s — the cable was innocent.

**Q: Why does replugging always fix it?**
A physical replug forces a full HPD + EDID + mode renegotiation while both ends are awake — a state in which negotiation works fine. Sleep/wake breaks precisely because both ends renegotiate *from standby*.

**Q: My monitor OSD has no deep-sleep option, only FreeSync and DP version.**
Same as ours — turning off FreeSync was enough. (The "DP version" OSD item only affects the monitor's DisplayPort input, irrelevant when connected via HDMI. If you later switch to USB-C→DP, set it to 1.2.)

## License

MIT
