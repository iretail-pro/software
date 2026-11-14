#!/usr/bin/env bash
# Builds the register (cashier) for iPhone and iPad without a brand, signs it
# for ad hoc distribution (the devices the provisioning profile lists) and
# exports cashier-<version>-ios.ipa, on a macOS runner.
#
#   scripts/ios-adhoc.sh <cashier checkout> <version> <out dir>
#
# From the environment (secrets of the release workflow):
#   P12           the Apple Distribution certificate and key, a .p12 as base64
#   P12_PASSWORD  its password
#   PROFILE       the ad hoc provisioning profile for the register's bundle
#                 id (pro.iretail.iretailCashier), as base64
#   TEAM          the Apple Developer team id
# The certificate goes into a throwaway keychain and the profile into the
# user's profiles folder, both removed when the script ends.
set -euo pipefail
src="${1:?usage: ios-adhoc.sh <cashier checkout> <version> <out dir>}"
version="${2:?version}"
out="${3:?out dir}"
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
bundle_id="$(sed -n 's/^BRAND_BUNDLE_ID = //p' "$src/ios/Flutter/BrandDefaults.xcconfig")"

cat > "$work/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>release-testing</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>manual</string>
  <key>provisioningProfiles</key>
  <dict><key>$bundle_id</key><string>$name</string></dict>
</dict>
</plist>
PLIST

cd "$src"
flutter pub get --enforce-lockfile
flutter build ios --release --no-codesign --dart-define=CASHIER_VERSION="$version"
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -archivePath "$work/Runner.xcarchive" -destination 'generic/platform=iOS' archive \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="Apple Distribution" \
  PROVISIONING_PROFILE_SPECIFIER="$name" OTHER_CODE_SIGN_FLAGS="--keychain $keychain"
xcodebuild -exportArchive -archivePath "$work/Runner.xcarchive" \
  -exportOptionsPlist "$work/ExportOptions.plist" -exportPath "$work/export"
mkdir -p "$out"
ipa="$(find "$work/export" -maxdepth 1 -name '*.ipa' | head -n 1)"
[ -n "$ipa" ] || { echo "ios-adhoc: no .ipa was exported" >&2; exit 1; }
cp "$ipa" "$out/cashier-$version-ios.ipa"
echo "exported cashier-$version-ios.ipa"
