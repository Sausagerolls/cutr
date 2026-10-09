#!/bin/zsh
# Captures App Store screenshots using the in-memory demo data.
# Usage: Scripts/screenshots.sh   (run from the repository root after building)
set -euo pipefail

IPHONE=${IPHONE:-"iPhone 17 Pro Max"}
IPAD=${IPAD:-"iPad Pro 13-inch (M5)"}
OUT=docs/screenshots
mkdir -p "$OUT"

xcodebuild -project Cutr.xcodeproj -scheme Cutr -configuration Release \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build build -quiet
APP=build/Build/Products/Release-iphonesimulator/Cutr.app

udid() { xcrun simctl list devices available | grep -F "$1 (" | head -1 | grep -oE '[0-9A-F-]{36}' }

shoot() {  # device-udid name screen appearance
  xcrun simctl ui "$1" appearance "$4"
  xcrun simctl launch --terminate-running-process "$1" com.jakewatts.cutr -demo -screen "$3" >/dev/null
  sleep 4
  xcrun simctl io "$1" screenshot "$OUT/$2.png" >/dev/null 2>&1
  echo "  $OUT/$2.png"
}

for device in "$IPHONE" "$IPAD"; do
  id=$(udid "$device")
  xcrun simctl boot "$id" 2>/dev/null || true
  xcrun simctl bootstatus "$id" -b >/dev/null
  xcrun simctl status_bar "$id" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
  xcrun simctl install "$id" "$APP"
done

iphone=$(udid "$IPHONE"); ipad=$(udid "$IPAD")
echo "iPhone ($IPHONE)"
shoot "$iphone" iphone-0-projects projects light
shoot "$iphone" iphone-1-list list light
shoot "$iphone" iphone-2-detail detail light
shoot "$iphone" iphone-3-layout layout light
shoot "$iphone" iphone-4-part part light
shoot "$iphone" iphone-5-layout-dark layout dark
echo "iPad ($IPAD)"
shoot "$ipad" ipad-1-detail detail light
shoot "$ipad" ipad-2-split split light
shoot "$ipad" ipad-3-detail-dark detail dark

for id in "$iphone" "$ipad"; do xcrun simctl ui "$id" appearance light; done
