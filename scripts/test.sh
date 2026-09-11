#!/bin/zsh
set -eu

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/bin/config-tests"
MODULE_CACHE="$ROOT/bin/module-cache"
HOST_ARCH="$(uname -m)"

case "$HOST_ARCH" in
  arm64|x86_64) ;;
  *)
    echo "unsupported test host architecture: $HOST_ARCH"
    exit 1
    ;;
esac

mkdir -p "$MODULE_CACHE"
env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE" \
  swiftc -target "$HOST_ARCH-apple-macosx14.0" \
  "$ROOT/src/Config.swift" \
  "$ROOT/src/ChatPage.swift" \
  "$ROOT/src/State.swift" \
  "$ROOT/src/Surfaces.swift" \
  "$ROOT/tests/config-tests.swift" \
  -o "$OUTPUT"
"$OUTPUT"
rm -f "$OUTPUT"
