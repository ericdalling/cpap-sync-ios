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
# Generate an opaque 1024px app icon with system Swift/AppKit (no external tools).
swift scripts/generate-icon.swift
xcodegen generate
