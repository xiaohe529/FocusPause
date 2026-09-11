#!/bin/sh
set -euo pipefail

# Swift Testing/XCTest runtime libraries come from the full Xcode toolchain.
# Override with CODEC_XCODE_DEVELOPER_DIR if your Xcode location differs.
DEVELOPER_DIR="${CODEC_XCODE_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

swift test --enable-code-coverage

BUILD_DIR=".build/${TARGET_VARIANT:-$(uname -m)}-apple-macosx/debug/codecov"
MAIN_BIN=".build/${TARGET_VARIANT:-$(uname -m)}-apple-macosx/debug/FocusPause"
HELPER_BIN=".build/${TARGET_VARIANT:-$(uname -m)}-apple-macosx/debug/FocusPauseHelper"

xcrun llvm-cov report \
  --instr-profile="$BUILD_DIR/default.profdata" \
  -object "$MAIN_BIN" \
  -object "$HELPER_BIN"
