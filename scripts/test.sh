#!/bin/zsh
set -eu

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/bin/config-tests"
swiftc -target arm64-apple-macosx14.0 "$ROOT/src/Config.swift" "$ROOT/src/ChatPage.swift" "$ROOT/tests/config-tests.swift" -o "$OUTPUT"
"$OUTPUT"
rm -f "$OUTPUT"
