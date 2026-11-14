#!/usr/bin/env bash
# Builds one image of the release as an OCI image layout saved as a tar,
# starts it once, and prints its manifest entry (contracts
# spec/RELEASES.md, "The manifest") as one line of JSON. Pushes nothing:
# the publish job pushes the tars by digest once the manifest is signed
# (scripts/push-image.sh).
#
#   scripts/image.sh <component> <context dir> <dockerfile> <version> <repository> <roles> <out dir> <oci-artifact.sh>
#
# Environment: KEY (the license issuer's public key, the node only),
# SOURCE_COMMIT (the source repository's commit, for the image's labels),
# CARGO_BUILD_JOBS (optional). Needs docker with buildx, jq, tar and
# sha256sum. Never prints a secret (there is none here).
set -euo pipefail
component="${1:?usage: image.sh <component> <context> <dockerfile> <version> <repository> <roles> <out> <oci-artifact.sh>}"
context="${2:?context}"
dockerfile="${3:?dockerfile}"
version="${4:?version}"
repository="${5:?repository}"
roles="${6:?roles}"
out="${7:?out dir}"
oci_artifact="${8:?oci-artifact.sh}"
platform=linux-x64
name="$component-$version-$platform.oci.tar"
mkdir -p "$out"

# BuildKit pinned by digest, as data-exchange-node's release.
buildkit="moby/buildkit:buildx-stable-1@sha256:cec9f139f45e93c5c69c60f8b07cfad9f43f4ef6b6a6cd917527fea5ff2e3dea"
docker buildx inspect release >/dev/null 2>&1 ||
  docker buildx create --name release --driver docker-container --driver-opt "image=$buildkit" >/dev/null

# The image says where it was built: this repository, at the source's commit.
args=(--builder release -f "$context/$dockerfile" --platform linux/amd64 --provenance=false --sbom=false
  --label "org.opencontainers.image.version=$version"
  --label "org.opencontainers.image.source=https://github.com/iretail-pro/software"
  --label "org.opencontainers.image.revision=${SOURCE_COMMIT:?SOURCE_COMMIT}")
case "$component" in
  node)
    args+=(--build-arg "BUILD_JOBS=${CARGO_BUILD_JOBS:-}" --build-arg "IRETAIL_LICENSE_PUBLIC_KEY=${KEY:-}") ;;
  updater)
    args+=(--build-arg "BUILD_JOBS=${CARGO_BUILD_JOBS:-}") ;;
esac
SOURCE_DATE_EPOCH="$(git -C "$context" log -1 --format=%ct)"
export SOURCE_DATE_EPOCH
docker buildx build "${args[@]}" \
  --output "type=oci,dest=$out/$name,name=$repository:$version,rewrite-timestamp=true" "$context" >&2

# It starts: each binary asks for its settings.
docker load -i "$out/$name" >/dev/null
starts() {
  local want="$1" log
  shift
  log="$(docker run --rm "$@" 2>&1 || true)"
  grep -q "$want" <<<"$log" || { echo "image.sh: $component did not start as expected" >&2; exit 1; }
}
case "$component" in
  node) starts 'use serve, migrate, init' "$repository:$version" bogus ;;
  updater)
    starts 'IRETAIL_UPDATER_TOKEN_FILE is not set' "$repository:$version"
    starts 'IRETAIL_UPDATER_PROXY_TOKEN_FILE is not set' --entrypoint /usr/local/bin/updater-proxy "$repository:$version"
    ;;
  console) : ;; # nginx and static files; the fragment's check reads its layout
esac

"$oci_artifact" "$out/$name" "$component" "$repository" "$roles" "$platform"
