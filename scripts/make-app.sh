#!/bin/bash
# Builds the release binary and wraps it into an ad-hoc signed ytd.app.
# Run from anywhere: bash scripts/make-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/ytd.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/ytd "$APP/Contents/MacOS/ytd"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>ir.abroun.ytd</string>
  <key>CFBundleName</key><string>ytd</string>
  <key>CFBundleDisplayName</key><string>ytd</string>
  <key>CFBundleExecutable</key><string>ytd</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
EOF

codesign --force -s - "$APP"

echo "OK: $APP"
echo "Run: open $APP"
