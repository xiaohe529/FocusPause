#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_DIR=".build/FocusPause.app"
APP_NAME="FocusPause"

# ---- ensure .app exists ----
if [ ! -d "$APP_DIR" ]; then
    echo "=== .app not found, building first ==="
    ./build-app.sh release
fi

VERSION="${1:-1.0.0}"
ZIP_FILE="${APP_NAME}-v${VERSION}.zip"

echo "=== Creating zip: ${ZIP_FILE} ==="

rm -f "$ZIP_FILE"
rm -rf "${APP_NAME}.app"

COPYFILE_DISABLE=1 cp -R "$APP_DIR" "${APP_NAME}.app"
xattr -cr "${APP_NAME}.app" 2>/dev/null || true
zip -r -q "$ZIP_FILE" "${APP_NAME}.app"
rm -rf "${APP_NAME}.app"

echo "=== Done: $ZIP_FILE ==="
echo "Upload to GitHub/Gitee Releases."
echo ""
echo "User install: unzip → drag to /Applications → right-click Open (first time)"