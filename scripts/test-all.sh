#!/bin/bash
# Runs every test: RockKit on macOS and on the iPad simulator, then the app's UI tests.
# Usage: scripts/test-all.sh            (override the simulator with DEVICE="iPad Air 13-inch (M4)")
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${DEVICE:-iPad Pro 11-inch (M5)}"
DESTINATION="platform=iOS Simulator,name=$DEVICE"

echo "▶ RockKit unit tests on macOS"
swift test --package-path Packages/RockKit

echo "▶ RockKit unit tests on $DEVICE"
(cd Packages/RockKit && xcodebuild test -scheme RockKit -destination "$DESTINATION" \
    -derivedDataPath ../../build/PackageDerivedData -collect-test-diagnostics never -quiet)

echo "▶ App build and UI tests on $DEVICE"
xcodebuild test -project RockID.xcodeproj -scheme RockID -destination "$DESTINATION" \
    -derivedDataPath build/DerivedData -collect-test-diagnostics never -quiet

echo "✅ All tests passed"
