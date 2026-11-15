#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=2.44.1
tool_dir="$PWD/build/tools"
mkdir -p "$tool_dir"
if ! command -v xcodegen >/dev/null || ! xcodegen --version | grep -Fq "$version"; then
  curl --fail --silent --show-error --location "https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip" -o "$tool_dir/xcodegen.zip"
  unzip -oq "$tool_dir/xcodegen.zip" -d "$tool_dir"
  export PATH="$tool_dir/xcodegen/bin:$PATH"
fi
xcodegen --version | grep -F "$version"
# Require the approved production artwork; never silently substitute a placeholder.
icon="CPAPSync/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
if [[ ! -f "$icon" ]]; then
  echo "Missing approved AppIcon.png; see docs/app-icon.md" >&2
  exit 1
fi
expected="d9ed953708500f8feae01d4514d13201303b9af203eb7b0e38fada0a4d32baa1"
actual="$(shasum -a 256 "$icon" | awk '{print $1}')"
if [[ "$actual" != "$expected" ]]; then
  echo "App icon differs from approved artwork; see docs/app-icon.md" >&2
  exit 1
fi
xcodegen generate
