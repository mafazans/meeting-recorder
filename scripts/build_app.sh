#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP_NAME="MeetingRecorder"
APP_BUNDLE=".build/${APP_NAME}.app"
BINARY_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
echo "Run: open $APP_BUNDLE"
