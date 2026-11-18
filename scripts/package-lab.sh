#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${APP_VERSION:?}" "${BUILD_NUMBER:?}"
out="$PWD/build/preview"
stage="$PWD/build/lab/CPAPSyncLab.swiftpm"
rm -rf "$PWD/build/lab"
mkdir -p "$stage/App" "$out"
cp tools/CPAPSyncLab/App/*.swift "$stage/App/"
# Swift Playgrounds on iPad does not reliably support local package dependencies.
# Embed the exact tested Swift source files at packaging time; no manually maintained copy.
cp Packages/CPAPSyncCore/Sources/CPAPSyncCore/*.swift "$stage/App/"
for file in Packages/CPAPSyncCore/Sources/CPAPSyncCore/*.swift; do
  cmp "$file" "$stage/App/$(basename "$file")"
done
sed -e "s/__VERSION__/$APP_VERSION/g" -e "s/__BUILD__/$BUILD_NUMBER/g" tools/CPAPSyncLab/Package.swift.template > "$stage/Package.swift"
cp tools/CPAPSyncLab/LabInfo.plist "$stage/"
plutil -lint "$stage/LabInfo.plist"
# Typecheck exact flattened source as an iOS module on the hosted Mac.
xcrun --sdk iphonesimulator swiftc -typecheck -swift-version 5 -target arm64-apple-ios17.0-simulator \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" "$stage/App/"*.swift
# Validate AppleProductTypes manifest using Xcode's package loader.
(cd "$stage" && xcodebuild -list)
rm -rf "$stage/.build" "$stage/.swiftpm" "$stage/Package.resolved"
ditto -c -k --keepParent "$stage" "$out/CPAPSyncLab-v$APP_VERSION-b$BUILD_NUMBER.swiftpm.zip"
python3 - "$out" "$stage" <<'PY'
import pathlib, sys, zipfile, json
out, stage = map(pathlib.Path, sys.argv[1:])
zip_path, = out.glob("*.swiftpm.zip")
with zipfile.ZipFile(zip_path) as z:
    assert z.testzip() is None
    for file in stage.rglob("*"):
        if file.is_file() and (file.suffix == ".swift" or file.name == "LabInfo.plist"):
            assert z.read(stage.name + "/" + str(file.relative_to(stage))) == file.read_bytes()
info_path = out / "build-info.json"
info = json.loads(info_path.read_text())
info["playground"] = zip_path.name
info["playground_core"] = "exact shared source at release commit"
info_path.write_text(json.dumps(info, indent=2) + "\n")
with (out / "release-notes.md").open("a") as f:
    f.write("\n\nIncludes CPAP Sync Lab for iPad Swift Playgrounds. Extract the ZIP in Files, then open the .swiftpm app. Physical card compatibility is not yet verified.\n")
PY
(cd "$out" && shasum -a 256 ./*.ipa ./*-dSYMs.zip ./*.swiftpm.zip build-info.json > SHA256SUMS.txt && shasum -a 256 -c SHA256SUMS.txt)
