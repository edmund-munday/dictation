#!/bin/sh
# Builds Dictation.app (release) into build/Dictation.app. Ad-hoc signed; grants nothing.
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product DictationApp
BIN="$(swift build -c release --show-bin-path)/DictationApp"
APP=build/Dictation.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dictation"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Dictation</string>
  <key>CFBundleDisplayName</key><string>Dictation</string>
  <key>CFBundleIdentifier</key><string>com.edmundmunday.dictation.hand</string>
  <key>CFBundleExecutable</key><string>Dictation</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Dictation listens only while you hold the talk key.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>On-device speech recognition is used when whisper.cpp is unavailable.</string>
</dict>
</plist>
PLIST
# Sign with a stable local identity when available so TCC grants survive rebuilds
# (ad-hoc signatures change cdhash every build). Override with DICTATION_SIGN_ID.
SIGN_ID="${DICTATION_SIGN_ID:-}"
if [ -z "$SIGN_ID" ]; then
  for c in "Dictation Local Code Signing" "Snip Local Code Signing"; do
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$c\""; then SIGN_ID="$c"; break; fi
  done
fi
if [ -n "$SIGN_ID" ]; then
  codesign --force --sign "$SIGN_ID" "$APP" >/dev/null 2>&1 || { echo "warning: signing with $SIGN_ID failed; using ad-hoc"; codesign --force --sign - "$APP" >/dev/null 2>&1; }
else
  codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc codesign failed"
fi
echo "Built $APP"
