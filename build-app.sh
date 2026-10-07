#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-debug}"
if [ "$CONFIG" = "release" ]; then
    BUILD_CONFIG="release"
    SWIFT_FLAGS="-c release"
else
    BUILD_CONFIG="debug"
    SWIFT_FLAGS=""
fi

echo "=== Building FocusPause + Helper ($BUILD_CONFIG) ==="

# Build for both architectures to create universal binaries.
# 注意：新版 swift-build 会把两个 --triple 的产物都写进同一个 `.build/out/Products/<Config>`，
# 后一次构建会覆盖前一次；旧的 `.build/<triple>/<config>` 硬编码则会拿到上一版工具链留下的
# 过期二进制（改了源码却"没生效"就是这个原因）。所以每次构建后立刻把产物另存到临时目录。
STAGE_DIR=".build/universal-stage"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

for ARCH in arm64-apple-macosx x86_64-apple-macosx; do
    SHORT="${ARCH%%-*}"
    echo "--- Building for $ARCH ---"
    swift build $SWIFT_FLAGS --triple "$ARCH"
    BIN_DIR="$(swift build $SWIFT_FLAGS --show-bin-path --triple "$ARCH")"
    cp "$BIN_DIR/FocusPause" "$STAGE_DIR/FocusPause-$SHORT"
    cp "$BIN_DIR/FocusPauseHelper" "$STAGE_DIR/FocusPauseHelper-$SHORT"
done

# Finder/桌面显示的是 .app **文件名**，不是 CFBundleName，所以文件名必须带 &。
BUNDLE_DIR=".build/Focus&Pause.app"
ARM_BIN="$STAGE_DIR/FocusPause-arm64"
ARM_HELPER="$STAGE_DIR/FocusPauseHelper-arm64"
X86_BIN="$STAGE_DIR/FocusPause-x86_64"
X86_HELPER="$STAGE_DIR/FocusPauseHelper-x86_64"

echo "=== Assembling .app bundle ==="
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"
mkdir -p "$BUNDLE_DIR/Contents/Helpers"

# Create universal binaries with lipo
if [ -f "$ARM_BIN" ] && [ -f "$X86_BIN" ]; then
    lipo -create "$ARM_BIN" "$X86_BIN" -output "$BUNDLE_DIR/Contents/MacOS/FocusPause"
    lipo -create "$ARM_HELPER" "$X86_HELPER" -output "$BUNDLE_DIR/Contents/Helpers/com.focuspause.helper"
    echo "Created universal binaries (arm64 + x86_64)"
elif [ -f "$ARM_BIN" ]; then
    cp "$ARM_BIN" "$BUNDLE_DIR/Contents/MacOS/FocusPause"
    cp "$ARM_HELPER" "$BUNDLE_DIR/Contents/Helpers/com.focuspause.helper"
    echo "arm64 only (x86_64 build unavailable)"
else
    echo "ERROR: No built binary found"
    exit 1
fi

cp BundleResources/Info.plist                     "$BUNDLE_DIR/Contents/Info.plist"
cp BundleResources/PkgInfo                         "$BUNDLE_DIR/Contents/PkgInfo"
cp BundleResources/AppIcon.icns                    "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
cp BundleResources/com.focuspause.helper.plist     "$BUNDLE_DIR/Contents/Resources/com.focuspause.helper.plist"

chmod +x "$BUNDLE_DIR/Contents/MacOS/FocusPause"
chmod +x "$BUNDLE_DIR/Contents/Helpers/com.focuspause.helper"

# Ad-hoc sign inner binaries first, then the main app
# Order matters: signing the outer bundle seals all inner content.
# If we sign the helper after the app, the seal breaks.
codesign --force --sign - "$BUNDLE_DIR/Contents/Helpers/com.focuspause.helper" 2>/dev/null || true
codesign --force --sign - "$BUNDLE_DIR/Contents/MacOS/FocusPause"

# Also copy helper + plist next to the arm64 executable for dev-mode (command-line) runs
BUILD_OUT_DIR="$(swift build $SWIFT_FLAGS --show-bin-path --triple arm64-apple-macosx)"
cp BundleResources/com.focuspause.helper.plist "$BUILD_OUT_DIR/com.focuspause.helper.plist"

# Strip Apple Double (._*) files — they corrupt pkg installers
find "$BUNDLE_DIR" -name "._*" -delete 2>/dev/null || true

echo "=== Bundle created: $BUNDLE_DIR ==="
echo "Run with: open $BUNDLE_DIR"
