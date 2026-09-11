#!/bin/zsh
# 安装当前用户的 LaunchAgent；不写入系统目录，不需要 sudo。
set -eu

# A LaunchAgent belongs to the logged-in Aqua user. Running this installer via
# sudo would target gui/0 instead and leave the bridge unavailable.
if [[ "$EUID" -eq 0 ]]; then
  echo "run install.sh as the logged-in user, not with sudo"
  exit 1
fi

ROOT="${0:A:h}"
LABEL="io.github.beingnotch.bridge"
INSTALL_DIR="$HOME/Library/Application Support/BeingNotch"
INSTALL_BIN="$INSTALL_DIR/being-notch"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_PATH="$AGENT_DIR/$LABEL.plist"
LOG_PATH="$HOME/Library/Logs/being-notch.log"
PORT=9021
PREBUILT_MARKER="$ROOT/PREBUILT"
SOURCE_BIN="$ROOT/bin/being-notch"

if [[ -f "$PREBUILT_MARKER" ]]; then
  if [[ ! -x "$SOURCE_BIN" ]]; then
    echo "release archive is missing its bridge binary"
    exit 1
  fi
  # A browser download may add quarantine metadata. Re-sign locally after
  # extraction so launchd can start the published binary without Xcode.
  xattr -d com.apple.quarantine "$SOURCE_BIN" 2>/dev/null || true
else
  "$ROOT/build.sh"
fi

ARCHS="$(lipo -archs "$SOURCE_BIN")"
if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
  echo "bridge binary is not universal (expected arm64 and x86_64)"
  exit 1
fi

mkdir -p "$AGENT_DIR"
cp "$ROOT/resources/$LABEL.plist" "$AGENT_PATH"
plutil -replace ProgramArguments -xml "<array><string>$INSTALL_BIN</string></array>" "$AGENT_PATH"
plutil -replace StandardOutPath -string "$LOG_PATH" "$AGENT_PATH"
plutil -replace StandardErrorPath -string "$LOG_PATH" "$AGENT_PATH"

if launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
  launchctl bootout "gui/$UID/$LABEL"
fi

# Do not replace an unrelated or older bridge that is already serving Atoll on
# the fixed loopback port. After stopping the prior bridge, rerunning this
# installer starts the public LaunchAgent normally.
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "port $PORT is already in use; the existing local bridge was left running"
  echo "stop the older bridge, then rerun: zsh install.sh"
  exit 0
fi

mkdir -p "$INSTALL_DIR"
rm -f "$INSTALL_BIN"
cp "$SOURCE_BIN" "$INSTALL_BIN"
codesign --force --sign - "$INSTALL_BIN"
codesign --verify "$INSTALL_BIN"

launchctl bootstrap "gui/$UID" "$AGENT_PATH"
echo "installed: $AGENT_PATH"
echo "open the Being tab in Atoll to connect your Being"
