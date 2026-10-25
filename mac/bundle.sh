#!/bin/sh
# Builds Remind.app next to this script: swift build -c release, wrapped.
set -e
cd "$(dirname "$0")"
swift build -c release
bin=$(swift build -c release --show-bin-path)
app=Remind.app/Contents
rm -rf Remind.app && mkdir -p $app/MacOS $app/Resources
cp "$bin/Remind" $app/MacOS/
cp -R "$bin"/*.bundle $app/Resources/ # the fonts
# the icon, drawn by icon.swift at every size macOS asks for
set=$(mktemp -d)/AppIcon.iconset && mkdir -p "$set"
swift icon.swift "$set/icon_512x512@2x.png"
for n in 16 32 128 256 512; do
  sips -z $n $n "$set/icon_512x512@2x.png" --out "$set/icon_${n}x${n}.png" >/dev/null
  sips -z $((n*2)) $((n*2)) "$set/icon_512x512@2x.png" --out "$set/icon_${n}x${n}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o $app/Resources/AppIcon.icns
cat > $app/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Remind</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>app.remind</string>
<key>CFBundleName</key><string>Remind</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSRemindersUsageDescription</key><string>Remind shows and edits your reminders through remindctl.</string>
<key>NSRemindersFullAccessUsageDescription</key><string>Remind shows and edits your reminders through remindctl.</string>
<key>NSCalendarsUsageDescription</key><string>Remind shows today's events through icalBuddy.</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>Remind shows today's events through icalBuddy.</string>
</dict></plist>
PLIST
# A stable identity, so macOS remembers the Reminders and Calendar access
# across rebuilds; ad hoc (asked again after every build) if there's none.
id=$(security find-identity -v -p codesigning | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"')
codesign -s "${id:--}" --force Remind.app
echo "built $(pwd)/Remind.app"
