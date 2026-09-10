#!/bin/zsh
# 安装当前用户的 LaunchAgent；不写入系统目录，不需要 sudo。
set -eu

ROOT="${0:A:h}"
LABEL="io.github.beingnotch.bridge"
INSTALL_DIR="$HOME/Library/Application Support/BeingNotch"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_PATH="$AGENT_DIR/$LABEL.plist"
LOG_PATH="$HOME/Library/Logs/being-notch.log"
PORT=9021

"$ROOT/build.sh"
mkdir -p "$AGENT_DIR"
cp "$ROOT/resources/$LABEL.plist" "$AGENT_PATH"
plutil -replace ProgramArguments.0 -string "$INSTALL_DIR/being-notch" "$AGENT_PATH"
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

launchctl bootstrap "gui/$UID" "$AGENT_PATH"
echo "installed: $AGENT_PATH"
echo "open the Being tab in Atoll to connect your Being"
