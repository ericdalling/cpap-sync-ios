#!/usr/bin/env bash
# Emit the same marketing version for the same source commit in both workflows.
set -euo pipefail
cd "$(dirname "$0")/.."
channel="${1:?preview or testflight required}"
case "$channel" in preview) channel_id=10;; testflight) channel_id=20;; *) exit 1;; esac
: "${GITHUB_RUN_NUMBER:?}" "${GITHUB_RUN_ATTEMPT:?}"
[[ "$GITHUB_RUN_NUMBER" =~ ^[1-9][0-9]{0,3}$ && "$GITHUB_RUN_ATTEMPT" =~ ^[1-9][0-9]?$ ]] || { echo "Build counter outside supported range" >&2; exit 1; }
# Version baseline is explicit and can be advanced at a release milestone.
read -r baseline anchor offset < config/version-baseline.txt
[[ "$offset" == 0 || "$offset" == 1 ]]
[[ "$baseline" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"; patch="${BASH_REMATCH[3]}"
[[ "$anchor" =~ ^[a-f0-9]{40}$ ]]
git merge-base --is-ancestor "$anchor" HEAD
# Require the anchor on first-parent history; no shallow clones or ambiguous branch ancestry.
git rev-list --first-parent HEAD | grep -Fx "$anchor" >/dev/null
distance="$(git rev-list --first-parent --count "$anchor..HEAD")"
(( distance >= offset )) || { echo "Version anchor offset not reached" >&2; exit 1; }
version="$major.$minor.$((patch + distance - offset))"
build="$GITHUB_RUN_NUMBER.$channel_id.$GITHUB_RUN_ATTEMPT"
printf 'APP_VERSION=%s\nBUILD_NUMBER=%s\n' "$version" "$build"
