#!/usr/bin/env bash
set -euo pipefail
sha=0123456789abcdef0123456789abcdef01234567
for good in v0.0.5 v0.0.5-b22.10.1-0123456789ab v0.0.5-b22.10.2-0123456789ab; do
  bash scripts/validate-release-tag.sh "$good" 0.0.5 "$sha"
done
for bad in main-v0.0.5-b22.10.1-0123456789ab v0.0.6 v0.0.5-b22.20.1-0123456789ab v0.0.5-b22.10.1-ffffffffffff v0.0.5-b22.10.1-0123456789ab-extra v0.0.5-b0.10.1-0123456789ab; do
  if bash scripts/validate-release-tag.sh "$bad" 0.0.5 "$sha" >/dev/null 2>&1; then echo "Accepted invalid tag: $bad" >&2; exit 1; fi
done
echo 'Release tag validation tests passed'
