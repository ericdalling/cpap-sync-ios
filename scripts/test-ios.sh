#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
version_args=()
if [[ -n "${APP_VERSION:-}" || -n "${BUILD_NUMBER:-}" ]]; then
  version_args=(MARKETING_VERSION="${APP_VERSION:?}" CURRENT_PROJECT_VERSION="${BUILD_NUMBER:?}")
fi
# Xcode versions on stable runners offer different simulator models.
# Pick an available iPhone instead of assuming the iPhone 17 exists.
destination="$(xcrun simctl list devices available | sed -nE 's/^[[:space:]]*(iPhone[^()]*) \(([0-9A-Fa-f-]{36})\).*/\2/p' | head -1)"
if [[ -z "$destination" ]]; then
  echo "No available iPhone simulator runtime found" >&2
  xcrun simctl list devices available >&2
  exit 1
fi
xcodebuild -project CPAPSync.xcodeproj -scheme CPAPSync \
  -destination "platform=iOS Simulator,id=$destination" \
  -derivedDataPath build/DerivedData -resultBundlePath build/Tests.xcresult \
  CODE_SIGNING_ALLOWED=NO ${version_args[@]+"${version_args[@]}"} test | tee build/test.log
