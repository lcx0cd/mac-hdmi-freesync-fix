#!/bin/bash
# hotplug-monitor.sh — 拔插测试监控（后台运行）
# 同时采集三路证据：系统日志流、显示模式采样、关键事件标记
TS=$(date +%Y%m%d-%H%M%S)
DIR="${1:-$HOME/.workbuddy/logs/hotplug-test-$TS}"
mkdir -p "$DIR" 2>/dev/null || true

# 三路证据文件
SYSLOG="$DIR/system.log"
STATUS="$DIR/mode-samples.log"

echo "[${TS}] === 监控开始，等待用户拔插 HDMI ===" >> "$STATUS"

# 后台：系统日志流（显示链路相关，尽量宽）
log stream --style compact \
  --predicate 'process == "WindowServer" OR process == "powerd" OR eventMessage CONTAINS[c] "hotplug" OR eventMessage CONTAINS[c] "display" OR eventMessage CONTAINS[c] "HDMI" OR eventMessage CONTAINS[c] "link"' \
  > "$SYSLOG" 2>&1 &
LOGPID=$!

# 前台循环：每 1 秒采样显示模式状态（检测画面丢失/恢复时刻）
while true; do
  TS2=$(date +%H:%M:%S.%3N 2>/dev/null || date +%H:%M:%S)
  MODE=$("$HOME/.workbuddy/bin/display-resync" --status 2>&1)
  echo "[$TS2] $MODE" >> "$STATUS"
  sleep 1
done &
LOOPPID=$!

cleanup() {
  kill $LOGPID $LOOPPID 2>/dev/null
  echo "[$(date +%H:%M:%S)] === 监控结束 ===" >> "$STATUS"
  exit 0
}
trap cleanup INT TERM

# 监控 10 分钟后自动结束
sleep 600
cleanup
