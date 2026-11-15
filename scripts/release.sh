#!/usr/bin/env bash
set -euo pipefail
umask 077
for name in P12_BASE64 P12_PASSWORD PROFILE_BASE64 ASC_KEY_BASE64 ASC_KEY_ID ASC_ISSUER_ID TEAM_ID BUILD_NUMBER; do
  if [[ -z "${!name:-}" ]]; then echo "Missing required configuration: $name" >&2; exit 1; fi
done
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo "Invalid team ID"; exit 1; }
[[ "$ASC_KEY_ID" =~ ^[A-Za-z0-9]+$ ]] || exit 1
[[ "$BUILD_NUMBER" =~ ^[0-9]+\.[0-9]+$ ]] || exit 1
tmp="$(mktemp -d)"
keychain="$tmp/signing.keychain-db"
keychain_password="$(openssl rand -hex 24)"
profile_path=""
cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  if [[ -n "$profile_path" ]]; then rm -f "$profile_path"; fi
  rm -rf "$tmp"
}
trap cleanup EXIT
printf '%s' "$P12_BASE64" | base64 -D > "$tmp/cert.p12"
printf '%s' "$PROFILE_BASE64" | base64 -D > "$tmp/profile.mobileprovision"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$tmp/cert.p12" -k "$keychain" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" login.keychain-db
security cms -D -i "$tmp/profile.mobileprovision" > "$tmp/profile.plist"
uuid="$(/usr/libexec/PlistBuddy -c 'Print UUID' "$tmp/profile.plist")"
profile_name="$(/usr/libexec/PlistBuddy -c 'Print Name' "$tmp/profile.plist")"
profile_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profile_dir"
profile_path="$profile_dir/$uuid.mobileprovision"
cp "$tmp/profile.mobileprovision" "$profile_path"
xcodebuild -project CPAPSync.xcodeproj -scheme CPAPSync -configuration Release -destination 'generic/platform=iOS' -archivePath build/CPAPSync.xcarchive DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution" PROVISIONING_PROFILE_SPECIFIER="$profile_name" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive
python3 - "$tmp/export.plist" "$TEAM_ID" "$profile_name" <<'PY'
import plistlib, sys
with open(sys.argv[1], "wb") as f:
    plistlib.dump({"method":"app-store-connect","teamID":sys.argv[2],"signingStyle":"manual","signingCertificate":"Apple Distribution","provisioningProfiles":{"com.ericdalling.cpapsync":sys.argv[3]},"manageAppVersionAndBuildNumber":False}, f)
PY
xcodebuild -exportArchive -archivePath build/CPAPSync.xcarchive -exportPath build/export -exportOptionsPlist "$tmp/export.plist"
mkdir -p "$tmp/private_keys"
printf '%s' "$ASC_KEY_BASE64" | base64 -D > "$tmp/private_keys/AuthKey_$ASC_KEY_ID.p8"
(
  cd "$tmp"
  xcrun altool --upload-app --type ios --file "$GITHUB_WORKSPACE/build/export/CPAPSync.ipa" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
)
