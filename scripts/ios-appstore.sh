#!/usr/bin/env bash
# Builds an app (the register, the back office or the customer app) for
# iPhone and iPad, signs it for App Store Connect and exports
# <file>-<version>-ios.ipa, on a macOS runner. The release's testflight job uploads it once the release is
# published; an App Store build installs on no device by itself.
#
#   scripts/ios-appstore.sh <app> <file> <checkout> <version> <build number> <bundle id> <out dir>
#
# The App Store's version is MAJOR.MINOR.PATCH, so a pre-release's suffix is
# left out of it; the build number must grow with every upload.
#
# From the environment (secrets of the release workflow):
#   P12           the Apple Distribution certificate and key, a .p12 as base64
#   P12_PASSWORD  its password
#   PROFILE       the App Store provisioning profile for <bundle id>, as base64
#   TEAM          the Apple Developer team id
# The certificate goes into a throwaway keychain and the profile into the
# user's profiles folder, both removed when the script ends.
set -euo pipefail
app="${1:?usage: ios-appstore.sh <app> <file> <checkout> <version> <build number> <bundle id> <out dir>}"
file="${2:?file}"
src="${3:?checkout}"
version="${4:?version}"
build="${5:?build number}"
bundle_id="${6:?bundle id}"
out="${7:?out dir}"
grep -Eq '^[1-9][0-9]*$' <<<"$build" || { echo "ios-appstore: the build number $build is not a whole number" >&2; exit 2; }
marketing="${version%%-*}"
: "${P12:?}" "${P12_PASSWORD:?}" "${PROFILE:?}" "${TEAM:?}"
work="$(mktemp -d)"
keychain="$work/build.keychain-db"
profiles="$HOME/Library/MobileDevice/Provisioning Profiles"
uuid=""
cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  [ -n "$uuid" ] && rm -f "$profiles/$uuid.mobileprovision"
  rm -rf "$work"
}
trap cleanup EXIT

printf '%s' "$P12" | base64 --decode > "$work/cert.p12"
printf '%s' "$PROFILE" | base64 --decode > "$work/profile.mobileprovision"
kc_password="$(openssl rand -hex 24)"
security create-keychain -p "$kc_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$kc_password" "$keychain"
security import "$work/cert.p12" -k "$keychain" -P "$P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$kc_password" "$keychain" >/dev/null
existing=()
while IFS= read -r k; do existing+=("$k"); done < <(security list-keychains -d user | sed 's/^ *"//; s/"$//')
security list-keychains -d user -s "$keychain" "${existing[@]}"

security cms -D -i "$work/profile.mobileprovision" > "$work/profile.plist"
uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$work/profile.plist")"
name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$work/profile.plist")"
mkdir -p "$profiles"
cp "$work/profile.mobileprovision" "$profiles/$uuid.mobileprovision"

cat > "$work/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>uploadSymbols</key><true/>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>manual</string>
  <key>provisioningProfiles</key>
  <dict><key>$bundle_id</key><string>$name</string></dict>
</dict>
</plist>
PLIST

cd "$src"
flutter pub get --enforce-lockfile
defines=()
[ "$app" = cashier ] && defines=(--dart-define=CASHIER_VERSION="$version")
flutter build ios --release --no-codesign --build-name="$marketing" --build-number="$build" "${defines[@]}"
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -archivePath "$work/Runner.xcarchive" -destination 'generic/platform=iOS' archive \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="Apple Distribution" \
  PROVISIONING_PROFILE_SPECIFIER="$name" OTHER_CODE_SIGN_FLAGS="--keychain $keychain"
xcodebuild -exportArchive -archivePath "$work/Runner.xcarchive" \
  -exportOptionsPlist "$work/ExportOptions.plist" -exportPath "$work/export"
mkdir -p "$out"
ipa="$(find "$work/export" -maxdepth 1 -name '*.ipa' | head -n 1)"
[ -n "$ipa" ] || { echo "ios-appstore: no .ipa was exported" >&2; exit 1; }
cp "$ipa" "$out/$file-$version-ios.ipa"
echo "exported $file-$version-ios.ipa"
