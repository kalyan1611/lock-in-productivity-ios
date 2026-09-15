#!/bin/bash

set -e

REPO="git@github.com:kalyan1611/lock-in-productivity-ios.git"
SCHEME="LockIn"
CONFIGURATION="Release"
DEVICE_ID="D5F42F2B-EA98-5121-936A-4998A5E3BD2B"

# ---------- ARGUMENT PARSING ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            CONFIGURATION="Debug"
            shift
            ;;
        *)
            echo "❌ Unknown argument: $1"
            echo "Usage: $0 [--debug]"
            exit 1
            ;;
    esac
done

TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

echo "📦 Cloning LockIn..."

git clone --quiet "$REPO" "$TEMP_DIR/lock-in-productivity-ios"

cd "$TEMP_DIR/lock-in-productivity-ios"

echo "🔨 Building LockIn ($CONFIGURATION)..."

BUILD_LOG="$TEMP_DIR/xcodebuild.log"

# Output is captured, not streamed — set -e is suppressed for just this
# command by the `if`, so a failing build falls through to the log dump
# below instead of silently exiting on the `set -e` at the top.
if ! xcodebuild \
    -project "LockIn.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$TEMP_DIR/build" \
    -allowProvisioningUpdates \
    build > "$BUILD_LOG" 2>&1; then
    echo "❌ Build failed. Full xcodebuild log:"
    echo ""
    cat "$BUILD_LOG"
    exit 1
fi

APP_PATH="$TEMP_DIR/build/Build/Products/$CONFIGURATION-iphoneos/LockIn.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ LockIn.app was not found."
    exit 1
fi

echo "📱 Installing LockIn..."

xcrun devicectl device install app \
    --device "$DEVICE_ID" \
    "$APP_PATH"

echo ""
echo "✅ LockIn installed successfully ($CONFIGURATION)."
echo "🧹 Temporary repository removed."