#!/bin/bash
# Builds universal (Apple Silicon + Intel) release binaries and assembles dist/ImageDiff.app,
# with imgdiff both inside the app and next to it.
#
# Usage: scripts/build-app.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0-dev}"
ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}" --product ImageDiff
swift build -c release "${ARCHS[@]}" --product imgdiff
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

rm -rf dist
APP=dist/ImageDiff.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ImageDiff" "$APP/Contents/MacOS/ImageDiff"
cp "$BIN/imgdiff" "$APP/Contents/MacOS/imgdiff"
cp "$BIN/imgdiff" dist/imgdiff
sed "s/@VERSION@/$VERSION/g" scripts/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc sign so the bundle is consistent; it is not notarised.
codesign --force --sign - "$APP/Contents/MacOS/imgdiff"
codesign --force --sign - "$APP"
codesign --force --sign - dist/imgdiff

echo "Built $APP and dist/imgdiff ($VERSION)"
