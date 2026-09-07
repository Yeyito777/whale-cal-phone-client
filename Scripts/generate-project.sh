#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f Config/Local.xcconfig || ! -f WhaleCal/Resources/Connection.local.json ]]; then
    echo "Copy Config/Local.example.xcconfig to Config/Local.xcconfig and Config/Connection.example.json to WhaleCal/Resources/Connection.local.json first." >&2
    exit 1
fi
xcodegen generate
# Keep the resolved graph in Git without publishing Xcode's generated signing metadata.
lockdir=WhaleCalPhoneClient.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$lockdir"
cp Package.resolved "$lockdir/Package.resolved"
