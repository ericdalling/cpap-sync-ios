#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
version_args=()
if [[ -n "${APP_VERSION:-}" || -n "${BUILD_NUMBER:-}" ]]; then
  version_args=(MARKETING_VERSION="${APP_VERSION:?}" CURRENT_PROJECT_VERSION="${BUILD_NUMBER:?}")
fi
xcodebuild -project CPAPSync.xcodeproj -scheme CPAPSync \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData -resultBundlePath build/Tests.xcresult \
  CODE_SIGNING_ALLOWED=NO ${version_args[@]+"${version_args[@]}"} test | tee build/test.log
