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

# Build for both architectures to create universal binaries
ARCHS=("arm64-apple-macosx" "x86_64-apple-macosx")
BUILT_BINS=()

for ARCH in "${ARCHS[@]}"; do
    echo "--- Building for $ARCH ---"
    swift build $SWIFT_FLAGS --triple "$ARCH"
    BUILT_BINS+=(".build/$ARCH/$BUILD_CONFIG/FocusPause")
    BUILT_BINS+=(".build/$ARCH/$BUILD_CONFIG/FocusPauseHelper")
done

BUNDLE_DIR=".build/FocusPause.app"
ARM_BIN=".build/arm64-apple-macosx/$BUILD_CONFIG/FocusPause"
ARM_HELPER=".build/arm64-apple-macosx/$BUILD_CONFIG/FocusPauseHelper"
X86_BIN=".build/x86_64-apple-macosx/$BUILD_CONFIG/FocusPause"
X86_HELPER=".build/x86_64-apple-macosx/$BUILD_CONFIG/FocusPauseHelper"

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
BUILD_OUT_DIR=".build/arm64-apple-macosx/$BUILD_CONFIG"
cp BundleResources/com.focuspause.helper.plist "$BUILD_OUT_DIR/com.focuspause.helper.plist"

# Strip Apple Double (._*) files — they corrupt pkg installers
find "$BUNDLE_DIR" -name "._*" -delete 2>/dev/null || true

echo "=== Bundle created: $BUNDLE_DIR ==="
echo "Run with: open $BUNDLE_DIR"
