#!/usr/bin/env bash
# Validate user-created semantic release tags and versioned CI prerelease tags.
set -euo pipefail
tag="${1:?release tag required}"
version="${2:?resolved marketing version required}"
commit="${3:?40-character commit SHA required}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$commit" =~ ^[0-9a-f]{40}$ ]] || exit 1
if [[ "$tag" == "v$version" ]]; then exit 0; fi
# Preview build is of the form N.10.ATTEMPT; signed build number remains distinct.
if [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-b([1-9][0-9]*\.10\.[1-9][0-9]*)-([a-f0-9]{12})$ ]]; then
  [[ "${BASH_REMATCH[1]}" == "$version" && "${BASH_REMATCH[3]}" == "${commit:0:12}" ]] && exit 0
fi
echo "Release tag does not match the expected version and commit" >&2
exit 1
