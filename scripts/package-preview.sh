#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GITHUB_SHA:?CI commit required}" "${GITHUB_RUN_ID:?CI run ID required}" \
  "${GITHUB_RUN_NUMBER:?CI run number required}" "${GITHUB_RUN_ATTEMPT:?CI attempt required}" \
  "${GITHUB_SERVER_URL:?CI server required}" "${GITHUB_REPOSITORY:?CI repository required}"
[[ "$GITHUB_SHA" =~ ^[a-f0-9]{40}$ ]]
for n in "$GITHUB_RUN_ID" "$GITHUB_RUN_NUMBER" "$GITHUB_RUN_ATTEMPT"; do [[ "$n" =~ ^[0-9]+$ ]]; done
[[ "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]]
out="$PWD/build/preview"
archive="$PWD/build/Preview.xcarchive"
rm -rf "$out" "$archive"
mkdir -p "$out"
build_number="${BUILD_NUMBER:?Resolve version first}"
app_version="${APP_VERSION:?Resolve version first}"
xcodebuild -project CPAPSync.xcodeproj -scheme CPAPSync -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" \
  -derivedDataPath build/PreviewDerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  DEBUG_INFORMATION_FORMAT=dwarf-with-dsym MARKETING_VERSION="$app_version" CURRENT_PROJECT_VERSION="$build_number" archive
app="$archive/Products/Applications/CPAPSync.app"
[[ -d "$app" && -f "$app/Info.plist" ]]
[[ -d "$archive/dSYMs/CPAPSync.app.dSYM" ]]
[[ ! -f "$app/embedded.mobileprovision" && ! -d "$app/_CodeSignature" ]]
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Info.plist")"
actual_build="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Info.plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$version" == "$app_version" && "$actual_build" == "$build_number" ]]
prefix="CPAPSync-v${version}-b${actual_build}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Payload"
ditto "$app" "$tmp/Payload/CPAPSync.app"
ditto -c -k --keepParent "$tmp/Payload" "$out/$prefix-unsigned.ipa"
ditto -c -k --keepParent "$archive/dSYMs" "$out/$prefix-dSYMs.zip"
python3 - "$out" "$version" "$actual_build" "$prefix" <<'PY'
import json, os, pathlib, subprocess, sys, zipfile
out, version, build, prefix = sys.argv[1:]
out = pathlib.Path(out)
ipa = out / (prefix + "-unsigned.ipa")
symbols = out / (prefix + "-dSYMs.zip")
for path, member in [(ipa, "Payload/CPAPSync.app/Info.plist"),
                     (symbols, "dSYMs/CPAPSync.app.dSYM/Contents/Info.plist")]:
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None, f"Corrupt ZIP: {path}"
        assert member in z.namelist(), f"Missing expected member: {member}"
env = os.environ
run_url = f"{env['GITHUB_SERVER_URL']}/{env['GITHUB_REPOSITORY']}/actions/runs/{env['GITHUB_RUN_ID']}"
info = {
    "version": version, "build": build, "commit": env["GITHUB_SHA"],
    "release_tag": f"v{version}-b{build}-{env['GITHUB_SHA'][:12]}",
    "run_id": env["GITHUB_RUN_ID"], "run_number": env["GITHUB_RUN_NUMBER"],
    "run_attempt": env["GITHUB_RUN_ATTEMPT"], "run_url": run_url,
    "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
    "platform": "iOS device", "configuration": "Release", "signing": "unsigned",
    "installable": False, "tests": "passed (preceding CI step)",
}
(out / "build-info.json").write_text(json.dumps(info, indent=2) + "\n")
(out / "release-notes.md").write_text(
    f"## CPAP Sync v{version} (build {build})\n\n"
    f"Marketing version: {version}\n\nCommit: `{info['commit']}`\n\n"
    f"[Successful CI run]({run_url})\n\n"
    "Unsigned device build for engineering traceability only. **Not installable on an iPhone.** "
    "TestFlight is the separate signed installation channel. "
    "Includes IPA, debug symbols, SHA-256 checksums and build metadata.\n"
)
PY
(cd "$out" && shasum -a 256 ./*.ipa ./*-dSYMs.zip build-info.json > SHA256SUMS.txt && shasum -a 256 -c SHA256SUMS.txt)
