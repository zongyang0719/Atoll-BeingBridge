#!/bin/zsh
# Build a redistributable, precompiled macOS archive without touching the
# user's installed LaunchAgent. The archive is published by release.yml.
set -eu

ROOT="${0:A:h:h}"
VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "usage: zsh scripts/package-release.sh vX.Y.Z"
  exit 1
fi

case "$VERSION" in
  v[0-9]*) ;;
  *)
    echo "release version must start with v and a number"
    exit 1
    ;;
esac

DIST_DIR="$ROOT/dist"
ASSET_NAME="atoll-being-bridge-$VERSION-macos-universal.zip"
ASSET_PATH="$DIST_DIR/$ASSET_NAME"
PACKAGE_NAME="Atoll-Being-Bridge"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/atoll-being-bridge.XXXXXX")"
PACKAGE_DIR="$STAGE_DIR/$PACKAGE_NAME"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

if [[ -e "$ASSET_PATH" ]]; then
  echo "release asset already exists: $ASSET_PATH"
  exit 1
fi

"$ROOT/build.sh"
SOURCE_BIN="$ROOT/bin/being-notch"
ARCHS="$(lipo -archs "$SOURCE_BIN")"
if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
  echo "release binary is not universal"
  exit 1
fi
codesign --verify "$SOURCE_BIN"

mkdir -p "$PACKAGE_DIR/bin" "$PACKAGE_DIR/resources" "$DIST_DIR"
cp "$SOURCE_BIN" "$PACKAGE_DIR/bin/being-notch"
cp "$ROOT/install.sh" "$ROOT/install.command" "$PACKAGE_DIR"
cp "$ROOT/resources/io.github.beingnotch.bridge.plist" "$PACKAGE_DIR/resources"
cp "$ROOT/README.md" "$ROOT/LICENSE" "$ROOT/NOTICE" "$PACKAGE_DIR"
print -r -- "$VERSION" > "$PACKAGE_DIR/PREBUILT"
chmod 755 "$PACKAGE_DIR/bin/being-notch" "$PACKAGE_DIR/install.sh" "$PACKAGE_DIR/install.command"

(
  cd "$STAGE_DIR"
  COPYFILE_DISABLE=1 COPY_EXTENDED_ATTRIBUTES_DISABLE=1 \
    /usr/bin/zip -qry "$ASSET_PATH" "$PACKAGE_NAME"
)
unzip -t "$ASSET_PATH" >/dev/null
if zipinfo -1 "$ASSET_PATH" | grep -E -q '^__MACOSX/|(^|/)\._|(^|/)\.DS_Store$'; then
  echo "release archive contains Finder metadata"
  exit 1
fi
for required in install.command install.sh PREBUILT bin/being-notch resources/io.github.beingnotch.bridge.plist README.md; do
  if ! zipinfo -1 "$ASSET_PATH" | grep -E -q "^$PACKAGE_NAME/$required$"; then
    echo "release archive is missing: $required"
    exit 1
  fi
done
shasum -a 256 "$ASSET_PATH" > "$ASSET_PATH.sha256"

echo "release package: $ASSET_PATH"
echo "checksum: $ASSET_PATH.sha256"
