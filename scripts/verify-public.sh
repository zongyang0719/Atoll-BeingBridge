#!/bin/zsh
# 公开前的最小静态检查：不输出命中的疑似密钥内容。
set -eu

ROOT="${0:A:h:h}"
for file in LICENSE NOTICE README.md install.sh install.command build.sh \
  scripts/package-release.sh scripts/release-notes.md \
  .github/workflows/verify.yml .github/workflows/release.yml; do
  if [[ ! -f "$ROOT/$file" ]]; then
    echo "missing required public file: $file"
    exit 1
  fi
done

PLIST_PROBE="$(mktemp "${TMPDIR:-/tmp}/being-notch-agent.XXXXXX")"
trap 'rm -f "$PLIST_PROBE"' EXIT
cp "$ROOT/resources/io.github.beingnotch.bridge.plist" "$PLIST_PROBE"
plutil -replace ProgramArguments -xml '<array><string>/tmp/being-notch</string></array>' "$PLIST_PROBE"
if [[ "$(plutil -extract ProgramArguments raw "$PLIST_PROBE")" != "1" ]] || \
  [[ "$(plutil -extract ProgramArguments.0 raw "$PLIST_PROBE")" != "/tmp/being-notch" ]] || \
  ! rg -q 'plutil -replace ProgramArguments -xml' "$ROOT/install.sh" || \
  ! rg -q 'EUID.*eq 0' "$ROOT/install.sh"; then
  echo "installer does not render exactly one bridge argument"
  exit 1
fi

RETIRED_PROVIDER="open""router"
PRIVATE_HOME="/""Users/"
LEGACY_DIRECTORY=".mtmr-""cards"
PERSONAL_LABEL="com.""marvic"
if rg -n -i "$RETIRED_PROVIDER|$PRIVATE_HOME|$LEGACY_DIRECTORY|$PERSONAL_LABEL" \
  "$ROOT/src" "$ROOT/resources" "$ROOT/install.sh" "$ROOT/build.sh" "$ROOT/scripts" \
  -g '!release-notes.md'; then
  echo "private or retired identifier remains"
  exit 1
fi

if rg -l -e 'sk-[A-Za-z0-9_-]{12,}|bearer[[:space:]]+[A-Za-z0-9._-]{12,}' "$ROOT" \
  -g '!.git/**' -g '!bin/**' -g '!build/**' -g '!*.app/**'; then
  echo "possible literal secret in source files"
  exit 1
fi

VERIFY_ARM64="$ROOT/bin/being-notch-verify-arm64"
VERIFY_X86_64="$ROOT/bin/being-notch-verify-x86_64"
VERIFY_BIN="$ROOT/bin/being-notch-verify"
MODULE_CACHE="$ROOT/bin/module-cache"
mkdir -p "$ROOT/bin" "$MODULE_CACHE"
rm -f "$VERIFY_ARM64" "$VERIFY_X86_64" "$VERIFY_BIN"
env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE" \
  swiftc -O -target arm64-apple-macosx14.0 "$ROOT"/src/*.swift -o "$VERIFY_ARM64"
env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE" \
  swiftc -O -target x86_64-apple-macosx14.0 "$ROOT"/src/*.swift -o "$VERIFY_X86_64"
lipo -create "$VERIFY_ARM64" "$VERIFY_X86_64" -output "$VERIFY_BIN"
if ! lipo -archs "$VERIFY_BIN" | rg -q 'arm64.*x86_64|x86_64.*arm64'; then
  echo "universal binary is missing a required architecture"
  exit 1
fi
rm -f "$VERIFY_ARM64" "$VERIFY_X86_64" "$VERIFY_BIN"
zsh "$ROOT/scripts/test.sh"
echo "public verification passed"
