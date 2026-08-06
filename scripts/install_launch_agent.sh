#!/bin/bash
# Registers MeetingRecorder to launch automatically at login via a LaunchAgent.
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"
APP_PATH="$PROJECT_DIR/.build/MeetingRecorder.app"
PLIST_LABEL="com.arifmafazan.meetingrecorder.launcher"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

if [ ! -d "$APP_PATH" ]; then
  echo "error: $APP_PATH not found. Run ./scripts/build_app.sh first." >&2
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>${APP_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo "Installed and loaded: $PLIST_PATH"
echo "MeetingRecorder will now launch automatically at every login/boot."
echo "To undo: launchctl unload $PLIST_PATH && rm $PLIST_PATH"
