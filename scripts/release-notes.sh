#!/usr/bin/env bash
# Writes a release's notes: <out>/en.md and ru.md (docs' releases/<version>/
# when docs has them, else the workflow's `notes` input as en.md), each with
# one sentence on what is and is not code-signed, and <out>/release.md, the
# GitHub Release's body (the English notes, the files and how to check them).
#
#   scripts/release-notes.sh <version> <docs releases dir> <signed dir> <mobile dir> <notes text> <out dir> [<guides dir>]
#
# <signed dir> holds <app>-<platform>.signed files, each "signed" or
# "unsigned", written by the desktop builds.
set -euo pipefail
version="${1:?usage: release-notes.sh <version> <docs releases> <signed dir> <mobile dir> <notes> <out>}"
docs="${2:?docs releases dir}"
signed_dir="${3:?signed dir}"
mobile_dir="${4:?mobile dir}"
notes="${5-}"
out="${6:?out dir}"
guides_dir="${7-}"
mkdir -p "$out"

for lang in en ru; do
  if [ -f "$docs/$version/$lang.md" ]; then cp "$docs/$version/$lang.md" "$out/$lang.md"; fi
done
if [ ! -f "$out/en.md" ]; then
  if [ -n "$notes" ]; then printf '%s\n' "$notes" > "$out/en.md"; else printf '# iRetail PRO %s\n' "$version" > "$out/en.md"; fi
fi

# Every leg of a platform must be signed for it to count as signed.
all_signed() {
  local platform="$1" f found=0
  for f in "$signed_dir"/*-"$platform".signed; do
    [ -e "$f" ] || continue
    found=1
    [ "$(cat "$f")" = signed ] || return 1
  done
  [ "$found" = 1 ]
}
windows=no macos=no
all_signed windows-x64 && windows=yes
all_signed macos-universal && macos=yes
case "$windows/$macos" in
  yes/yes) en="" ru="" ;;
  no/no)
    en="The Windows and macOS installers of this release are not code-signed yet: SmartScreen and Gatekeeper warn before they run. The SHA-256 of each file in the signed manifest is the check that matters."
    ru="Установщики этого выпуска для Windows и macOS пока не подписаны: SmartScreen и Gatekeeper предупредят перед запуском. Проверяйте SHA-256 каждого файла по подписанному манифесту." ;;
  no/yes)
    en="The Windows installers of this release are not code-signed yet: SmartScreen warns before they run. The macOS ones are signed with a Developer ID and notarized. The SHA-256 of each file in the signed manifest is the check that matters."
    ru="Установщики этого выпуска для Windows пока не подписаны: SmartScreen предупредит перед запуском. Сборки для macOS подписаны Developer ID и нотаризованы. Проверяйте SHA-256 каждого файла по подписанному манифесту." ;;
  yes/no)
    en="The macOS installers of this release are not code-signed or notarized yet: Gatekeeper warns before they run. The Windows ones are signed. The SHA-256 of each file in the signed manifest is the check that matters."
    ru="Установщики этого выпуска для macOS пока не подписаны и не нотаризованы: Gatekeeper предупредит перед запуском. Сборки для Windows подписаны. Проверяйте SHA-256 каждого файла по подписанному манифесту." ;;
esac
add_once() {
  local file="$1" line="$2"
  [ -n "$line" ] && [ -f "$file" ] || return 0
  grep -qxF "$line" "$file" || printf '\n%s\n' "$line" >> "$file"
}
add_once "$out/en.md" "$en"
add_once "$out/ru.md" "$ru"

{
  cat "$out/en.md"
  echo
  echo "## Files"
  echo
  echo "- \`manifest.json\`: the signed release manifest. Every file of the release is listed in it with its SHA-256 and size; the apps, the node and the updater check it with the release keys they embed."
  echo "- \`iretail-$version.tar\`: the air-gapped bundle (the manifest and every artifact), for \`node release import\` at a hub."
  echo "- \`iretail-deploy-$version.tar.gz\`: the deployment kit (compose files, chart, install scripts)."
  echo "- Container images: \`ghcr.io/iretail-pro/software/node:$version\`, \`software/updater:$version\`, \`software/console:$version\`, by the digests in the manifest."
  if compgen -G "$mobile_dir/*" >/dev/null; then
    echo "- Phones and handhelds (outside the signed manifest; see \`SHA256SUMS\`):"
    for f in "$mobile_dir"/*; do echo "  - \`${f##*/}\`"; done
  fi
  if [ -n "$guides_dir" ] && compgen -G "$guides_dir/*.pdf" >/dev/null; then
    echo "- Guides (PDF, \`en\` English, \`ru\` Russian): \`guide-admin-…\` installing and running a store's server or a hub (the containers), the gateway, backups and updates; \`guide-cashier-…\` the register; \`guide-manager-…\` the back office and the hub's console; \`guide-hardware-…\` connecting devices; \`guide-us-pack-…\` what a US store adds:"
    for f in "$guides_dir"/*.pdf; do echo "  - \`${f##*/}\`"; done
  fi
  echo "- \`SHA256SUMS\`: the SHA-256 of every file here."
  if [ -f "$out/ru.md" ]; then
    echo
    echo "Release notes in Russian: \`notes-ru.md\`."
  fi
} > "$out/release.md"
