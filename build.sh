#!/bin/zsh
# 编译并安装 bridge。首次配置在 Atoll 的 Being tab 内完成。
set -eu

ROOT="${0:A:h}"
BIN_DIR="$ROOT/bin"
BRIDGE_BIN="$BIN_DIR/being-notch"
ARM64_BIN="$BIN_DIR/being-notch-arm64"
X86_64_BIN="$BIN_DIR/being-notch-x86_64"
INSTALL_DIR="$HOME/Library/Application Support/BeingNotch"
MACOS_VERSION="14.0"

mkdir -p "$BIN_DIR" "$INSTALL_DIR"
# Explicitly pin both deployment targets. On preview macOS toolchains, Swift's
# implicit target can be newer than the running OS, which makes Finder reject
# an otherwise valid app bundle before it reaches our settings code.
rm -f "$ARM64_BIN" "$X86_64_BIN"
swiftc -O -target "arm64-apple-macosx$MACOS_VERSION" "$ROOT"/src/*.swift -o "$ARM64_BIN"
swiftc -O -target "x86_64-apple-macosx$MACOS_VERSION" "$ROOT"/src/*.swift -o "$X86_64_BIN"
lipo -create "$ARM64_BIN" "$X86_64_BIN" -output "$BRIDGE_BIN"
rm -f "$ARM64_BIN" "$X86_64_BIN"
codesign --force --sign - "$BRIDGE_BIN"

# 不直接覆盖正在被内核映射的旧二进制，避免 ad-hoc 签名缓存不一致。
rm -f "$INSTALL_DIR/being-notch"
cp "$BRIDGE_BIN" "$INSTALL_DIR/being-notch"
codesign --force --sign - "$INSTALL_DIR/being-notch"

codesign --verify "$INSTALL_DIR/being-notch"
echo "bridge:   $INSTALL_DIR/being-notch"
