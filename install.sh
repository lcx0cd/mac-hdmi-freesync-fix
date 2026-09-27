#!/bin/bash
# install.sh — build display-resync, install it, and set up the wake daemon
# Works on Apple Silicon Macs with Xcode Command Line Tools (swiftc).
set -e

PREFIX="${HOME}/.local/bin"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)/Sources/display-resync"
BIN_NAME="display-resync"

echo "==> Compiling ${BIN_NAME}..."
mkdir -p "${PREFIX}"
swiftc -O "${SRC_DIR}/main.swift" -o "${PREFIX}/${BIN_NAME}"
echo "    Installed: ${PREFIX}/${BIN_NAME}"

# Ensure ~/.local/bin is on PATH
case ":${PATH}:" in
  *":${PREFIX}:"*) ;;
  *)
    RC="${HOME}/.zshrc"
    [ -n "${BASH_VERSION}" ] && [ ! -f "${RC}" ] && RC="${HOME}/.bashrc"
    echo "export PATH=\"${PREFIX}:\$PATH\"" >> "${RC}"
    echo "    Added ${PREFIX} to PATH in ${RC} (restart your shell to apply)"
    ;;
esac

# Try LaunchAgent first (most reliable, survives without opening a terminal).
# Known issue: on some macOS 26 setups launchctl rejects ALL new user agents
# (Bootstrap failed: 5). We detect that and fall back to a shell-rc daemon.
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST="${PLIST_DIR}/com.${BIN_NAME}.plist"
LOG_DIR="${HOME}/.local/state/${BIN_NAME}"
mkdir -p "${PLIST_DIR}" "${LOG_DIR}"

cat > "${PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.${BIN_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${PREFIX}/${BIN_NAME}</string>
        <string>--watch</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>${LOG_DIR}/watch.log</string>
    <key>StandardErrorPath</key><string>${LOG_DIR}/watch.log</string>
    <key>ProcessType</key><string>Background</string>
</dict>
</plist>
EOF

LA_OK=0
launchctl bootout "gui/$(id -u)/com.${BIN_NAME}" 2>/dev/null || true
if launchctl bootstrap "gui/$(id -u)" "${PLIST}" 2>/dev/null; then
  LA_OK=1
  echo "==> LaunchAgent installed (auto-start at login, wake watcher active)"
else
  echo "!!  launchctl rejected the agent (common on some macOS 26 setups) — using shell-rc fallback"
  rm -f "${PLIST}"
fi

if [ "${LA_OK}" -eq 0 ]; then
  RC="${HOME}/.zshrc"
  [ -n "${BASH_VERSION}" ] && [ ! -f "${RC}" ] && RC="${HOME}/.bashrc"
  if ! grep -q "${BIN_NAME} --watch" "${RC}" 2>/dev/null; then
    cat >> "${RC}" <<EOF

# ${BIN_NAME}: HDMI wake-resync daemon (auto-fix display artifacts after wake)
if ! pgrep -f "${BIN_NAME} --watch" >/dev/null 2>&1; then
  nohup "\$HOME/.local/bin/${BIN_NAME}" --watch >/dev/null 2>&1 &
fi
EOF
    echo "==> Daemon auto-start block added to ${RC}"
    # start it now
    nohup "${PREFIX}/${BIN_NAME}" --watch >/dev/null 2>&1 &
    echo "==> Daemon started (PID $(pgrep -f "${BIN_NAME} --watch" | head -1))"
  else
    echo "==> Daemon block already present in ${RC}"
  fi
fi

echo
echo "Done. Usage:"
echo "  ${BIN_NAME}            # one-shot resync"
echo "  ${BIN_NAME} --watch    # wake watcher (already running if daemon installed)"
echo "  ${BIN_NAME} --status   # show current mode"
echo
echo "Also remember: turn OFF FreeSync/Adaptive-Sync in your monitor's OSD —"
echo "that is the actual root cause for most wake-artifact cases."
