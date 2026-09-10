#!/bin/zsh
# 公开前的最小静态检查：不输出命中的疑似密钥内容。
set -eu

ROOT="${0:A:h:h}"
for file in LICENSE NOTICE README.md install.sh build.sh .github/workflows/verify.yml; do
  if [[ ! -f "$ROOT/$file" ]]; then
    echo "missing required public file: $file"
    exit 1
  fi
done

RETIRED_PROVIDER="open""router"
PRIVATE_HOME="/""Users/"
LEGACY_DIRECTORY=".mtmr-""cards"
PERSONAL_LABEL="com.""marvic"
if rg -n -i "$RETIRED_PROVIDER|$PRIVATE_HOME|$LEGACY_DIRECTORY|$PERSONAL_LABEL" "$ROOT" \
  -g '!bin/**' -g '!build/**' -g '!*.app/**'; then
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
mkdir -p "$ROOT/bin"
rm -f "$VERIFY_ARM64" "$VERIFY_X86_64" "$VERIFY_BIN"
swiftc -O -target arm64-apple-macosx14.0 "$ROOT"/src/*.swift -o "$VERIFY_ARM64"
swiftc -O -target x86_64-apple-macosx14.0 "$ROOT"/src/*.swift -o "$VERIFY_X86_64"
lipo -create "$VERIFY_ARM64" "$VERIFY_X86_64" -output "$VERIFY_BIN"
if ! lipo -archs "$VERIFY_BIN" | rg -q 'arm64.*x86_64|x86_64.*arm64'; then
  echo "universal binary is missing a required architecture"
  exit 1
fi
rm -f "$VERIFY_ARM64" "$VERIFY_X86_64" "$VERIFY_BIN"
zsh "$ROOT/scripts/test.sh"
echo "public verification passed"
