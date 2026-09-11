#!/bin/zsh
# 编译 universal bridge；安装由 install.sh 负责。
set -eu

ROOT="${0:A:h}"
BIN_DIR="$ROOT/bin"
BRIDGE_BIN="$BIN_DIR/being-notch"
ARM64_BIN="$BIN_DIR/being-notch-arm64"
X86_64_BIN="$BIN_DIR/being-notch-x86_64"
MACOS_VERSION="14.0"
MODULE_CACHE="$BIN_DIR/module-cache"

mkdir -p "$BIN_DIR" "$MODULE_CACHE"
# Explicitly pin both deployment targets. On preview macOS toolchains, Swift's
# implicit target can be newer than the running OS, which makes Finder reject
# an otherwise valid app bundle before it reaches our settings code.
rm -f "$ARM64_BIN" "$X86_64_BIN"
env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE" \
  swiftc -O -target "arm64-apple-macosx$MACOS_VERSION" "$ROOT"/src/*.swift -o "$ARM64_BIN"
env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE" \
  swiftc -O -target "x86_64-apple-macosx$MACOS_VERSION" "$ROOT"/src/*.swift -o "$X86_64_BIN"
lipo -create "$ARM64_BIN" "$X86_64_BIN" -output "$BRIDGE_BIN"
rm -f "$ARM64_BIN" "$X86_64_BIN"
codesign --force --sign - "$BRIDGE_BIN"
codesign --verify "$BRIDGE_BIN"
echo "built: $BRIDGE_BIN ($(lipo -archs "$BRIDGE_BIN"))"
