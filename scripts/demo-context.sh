#!/usr/bin/env bash
# Puts together the demo image's build context (demo/Dockerfile; README,
# "The demo") for a published release: the node and the back office's
# browser build from the release's own images, pulled by the digests its
# signed manifest names; the gateway and its emulators built from
# device-gateway; the register's browser build; deploy's pilot stores and
# load-pilot.py.
#
#   scripts/demo-context.sh <version> <out dir>
#
# Environment:
#   MANIFEST      the release's manifest.json (checked here with deploy's
#                 scripts/verify-manifest.sh and its release-keys.txt)
#   DEPLOY_DIR    a checkout of deploy at v<version>
#   GATEWAY_DIR   a checkout of device-gateway at v<version>
#   REGISTER_WEB  the register's `flutter build web --base-href /register/`
#   NODE_ARM64    optional: the node built for linux/arm64 from
#                 data-exchange-node at v<version>; without it the context
#                 holds linux/amd64 only
# Prints the platforms the context holds (linux/amd64[,linux/arm64]).
# Needs docker, jq, go, openssl.
set -euo pipefail
version="${1:?usage: demo-context.sh <version> <out dir>}"
out="${2:?out dir}"
here="$(cd "$(dirname "$0")/.." && pwd)"
: "${MANIFEST:?MANIFEST}" "${DEPLOY_DIR:?DEPLOY_DIR}" "${GATEWAY_DIR:?GATEWAY_DIR}" "${REGISTER_WEB:?REGISTER_WEB}"
[ -f "$REGISTER_WEB/index.html" ] || { echo "demo-context: $REGISTER_WEB has no index.html" >&2; exit 1; }
grep -q '<base href="/register/">' "$REGISTER_WEB/index.html" ||
  { echo "demo-context: the register's build must be made with --base-href /register/" >&2; exit 1; }

# The manifest is the release's: signed by a release key and of this version.
keys=()
while IFS= read -r line; do
  case "$line" in '#'* | '') ;; *) keys+=("$line") ;; esac
done < "$DEPLOY_DIR/scripts/release-keys.txt"
"$DEPLOY_DIR/scripts/verify-manifest.sh" --version "$version" "$MANIFEST" "${keys[@]}" >&2
digest() {
  jq -er --arg c "$1" '.manifest.artifacts[] | select(.kind == "image" and .component == $c and .platform == "linux-x64") | "\(.image)@\(.digest)"' "$MANIFEST"
}

rm -rf "$out"
mkdir -p "$out/bin/amd64" "$out/web" "$out/pilots"
take() { # take <image@digest> <path in the image> <dest>
  local id
  docker pull -q --platform linux/amd64 "$1" >/dev/null
  id="$(docker create --platform linux/amd64 "$1")"
  docker cp "$id:$2" "$3" >/dev/null
  docker rm "$id" >/dev/null
}
take "$(digest node)" /usr/local/bin/node "$out/bin/amd64/node"
take "$(digest console)" /usr/share/nginx/html "$out/web/manager"
cp -R "$REGISTER_WEB" "$out/web/register"

platforms=linux/amd64
arches=(amd64)
if [ -n "${NODE_ARM64:-}" ]; then
  mkdir -p "$out/bin/arm64"
  install -m 0755 "$NODE_ARM64" "$out/bin/arm64/node"
  platforms=linux/amd64,linux/arm64
  arches+=(arm64)
fi
for arch in "${arches[@]}"; do
  (cd "$GATEWAY_DIR" && CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -trimpath -ldflags "-s -w" \
    -o "$out/bin/$arch/" ./cmd/gateway ./cmd/emulator)
done

for p in supermarket pharmacy grocery coffee-shop pizzeria apparel electronics; do
  cp "$DEPLOY_DIR/demo/pilots/$p.json" "$out/pilots/"
done
cp "$DEPLOY_DIR/scripts/load-pilot.py" "$out/"
cp "$here/demo/"{Dockerfile,run.py,nginx.conf,nginx.conf.template,gateway.yaml,index.html,devices.html} "$out/"
echo "$platforms"
