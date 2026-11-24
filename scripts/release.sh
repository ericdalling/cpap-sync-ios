#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
for name in ASC_KEY_ID ASC_ISSUER_ID TEAM_ID BUILD_NUMBER APP_VERSION; do
  if [[ -z "${!name:-}" ]]; then echo "Missing required configuration: $name" >&2; exit 1; fi
done
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo "Invalid team ID"; exit 1; }
[[ "$ASC_KEY_ID" =~ ^[A-Za-z0-9]+$ ]] || exit 1
[[ "$ASC_ISSUER_ID" =~ ^[A-Fa-f0-9-]{36}$ ]] || exit 1
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]{0,3}\.20\.[1-9][0-9]?$ ]] || exit 1
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
tmp="$(mktemp -d)"
keychain="$tmp/signing.keychain-db"
profile_path=""
cleanup() {
  if [[ -f "$keychain" ]]; then security delete-keychain "$keychain" >/dev/null 2>&1 || true; fi
  if [[ -n "$profile_path" ]]; then rm -f "$profile_path"; fi
  rm -rf "$tmp"
}
trap cleanup EXIT
key="$tmp/AuthKey_$ASC_KEY_ID.p8"
if [[ -n "${ASC_API_PRIVATE_KEY:-}" ]]; then
  printf '%s\n' "$ASC_API_PRIVATE_KEY" > "$key"
elif [[ -n "${ASC_KEY_BASE64:-}" ]]; then
  printf '%s' "$ASC_KEY_BASE64" | base64 -D > "$key"
else
  echo "Missing App Store Connect API private key" >&2; exit 1
fi
openssl pkey -in "$key" -noout >/dev/null
auth=(-allowProvisioningUpdates -authenticationKeyPath "$key" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
archive=(xcodebuild -project CPAPSync.xcodeproj -scheme CPAPSync -configuration Release -destination 'generic/platform=iOS' -archivePath build/CPAPSync.xcarchive DEVELOPMENT_TEAM="$TEAM_ID" MARKETING_VERSION="$APP_VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
mode="${SIGNING_MODE:-automatic}"
profile_name=""
case "$mode" in
 automatic)
  # Force distribution signing for TestFlight. Without this XcodeGen defaults to
  # an iOS development profile and fails when the team has no registered devices.
  "${archive[@]}" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Distribution" "${auth[@]}" archive
  ;;
 manual)
  for name in P12_BASE64 P12_PASSWORD PROFILE_BASE64; do
    if [[ -z "${!name:-}" ]]; then echo "Missing manual signing configuration: $name" >&2; exit 1; fi
  done
  printf '%s' "$P12_BASE64" | base64 -D > "$tmp/cert.p12"
  printf '%s' "$PROFILE_BASE64" | base64 -D > "$tmp/profile.mobileprovision"
  password="$(openssl rand -hex 24)"
  security create-keychain -p "$password" "$keychain"
  security set-keychain-settings -lut 3600 "$keychain"
  security unlock-keychain -p "$password" "$keychain"
  security import "$tmp/cert.p12" -k "$keychain" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
  security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
  security list-keychains -d user -s "$keychain" login.keychain-db
  security cms -D -i "$tmp/profile.mobileprovision" > "$tmp/profile.plist"
  uuid="$(/usr/libexec/PlistBuddy -c 'Print UUID' "$tmp/profile.plist")"
  profile_name="$(/usr/libexec/PlistBuddy -c 'Print Name' "$tmp/profile.plist")"
  profile_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  mkdir -p "$profile_dir"
  profile_path="$profile_dir/$uuid.mobileprovision"
  cp "$tmp/profile.mobileprovision" "$profile_path"
  "${archive[@]}" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution" PROVISIONING_PROFILE_SPECIFIER="$profile_name" archive
  ;;
 *) echo "Unknown signing mode" >&2; exit 1 ;;
esac
app_plist="build/CPAPSync.xcarchive/Products/Applications/CPAPSync.app/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_plist")" == "$APP_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app_plist")" == "$BUILD_NUMBER" ]]
echo "Verified signed archive version $APP_VERSION build $BUILD_NUMBER"
python3 - "$tmp/export.plist" "$TEAM_ID" "$mode" "$profile_name" <<'PY'
import plistlib, sys
path, team, mode, profile = sys.argv[1:]
options = {"method": "app-store-connect", "destination": "upload", "teamID": team,
           "signingStyle": mode, "manageAppVersionAndBuildNumber": False}
if mode == "manual":
    options.update(signingCertificate="Apple Distribution",
                   provisioningProfiles={"com.ericdalling.cpapsync": profile})
with open(path, "wb") as f:
    plistlib.dump(options, f)
PY
# Xcode performs the upload; the API key remains in the temporary directory.
xcodebuild -exportArchive -archivePath build/CPAPSync.xcarchive -exportPath build/export -exportOptionsPlist "$tmp/export.plist" "${auth[@]}"
echo "Upload command succeeded. Verify App Store Connect processing and internal TestFlight separately."
