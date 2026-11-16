#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q
git config user.name 'Version Test'
git config user.email 'version-test@example.invalid'
git commit --allow-empty -qm baseline
anchor="$(git rev-parse HEAD)"
mkdir -p scripts config
cp "$root/scripts/resolve-version.sh" scripts/
printf '0.0.1 %s 0\n' "$anchor" > config/version-baseline.txt
resolve() { GITHUB_RUN_NUMBER=12 GITHUB_RUN_ATTEMPT="${2:-1}" bash scripts/resolve-version.sh "$1"; }
expect() { [[ "$1" == "$2" ]] || { printf 'Expected:\n%s\nActual:\n%s\n' "$2" "$1" >&2; exit 1; }; }
expect "$(resolve preview)" $'APP_VERSION=0.0.1\nBUILD_NUMBER=12.10.1'
git add .
git commit -qm first
expect "$(resolve preview)" $'APP_VERSION=0.0.2\nBUILD_NUMBER=12.10.1'
expect "$(resolve preview 2)" $'APP_VERSION=0.0.2\nBUILD_NUMBER=12.10.2'
expect "$(resolve testflight)" $'APP_VERSION=0.0.2\nBUILD_NUMBER=12.20.1'
git commit --allow-empty -qm second
expect "$(resolve preview)" $'APP_VERSION=0.0.3\nBUILD_NUMBER=12.10.1'
printf '0.1.0 %s 1\n' "$(git rev-parse HEAD)" > config/version-baseline.txt
git add config
git commit -qm milestone
expect "$(resolve preview)" $'APP_VERSION=0.1.0\nBUILD_NUMBER=12.10.1'
if GITHUB_RUN_NUMBER=10000 GITHUB_RUN_ATTEMPT=1 bash scripts/resolve-version.sh preview >/dev/null 2>&1; then
  echo 'Expected invalid counter to fail' >&2; exit 1
fi
echo 'Version resolver tests passed'
