#!/usr/bin/env bash
# Static guard against reintroducing development-provisioning or conflicting
# Apple Distribution identity during automatic TestFlight archiving.
set -euo pipefail
grep -Fq '"${archive[@]}" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO archive' scripts/release.sh
! grep -Fq 'CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY=' scripts/release.sh
grep -Fq '"signingStyle": mode' scripts/release.sh
grep -Fq '"method": "app-store-connect"' scripts/release.sh
grep -Fq 'xcodebuild -exportArchive' scripts/release.sh
echo 'Signing orchestration checks passed'
