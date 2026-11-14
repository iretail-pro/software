#!/usr/bin/env bash
# Pushes one image of a signed release from its OCI layout tar, by digest:
# the registry must then serve exactly the digest the manifest names, and
# the tag <version> is set on it.
#
#   scripts/push-image.sh <file.oci.tar> <repository> <version> <digest>
#
# Environment: GH_TOKEN and GITHUB_ACTOR (ghcr.io). Needs skopeo.
set -euo pipefail
file="${1:?usage: push-image.sh <file.oci.tar> <repository> <version> <digest>}"
repository="${2:?repository}"
version="${3:?version}"
digest="${4:?digest}"
: "${GH_TOKEN:?GH_TOKEN is required to push}"
skopeo login "${repository%%/*}" -u "${GITHUB_ACTOR:?GITHUB_ACTOR}" --password-stdin <<<"$GH_TOKEN" >/dev/null
# A tag already on the registry is never moved: a version is published once.
if skopeo inspect --raw "docker://$repository:$version" >/dev/null 2>&1; then
  have="$(skopeo inspect --format '{{.Digest}}' "docker://$repository:$version")"
  [ "$have" = "$digest" ] || { echo "push-image: $repository:$version is $have already, not $digest" >&2; exit 1; }
  echo "$repository:$version is $digest already"
  exit 0
fi
skopeo copy --preserve-digests "oci-archive:$file" "docker://$repository:$version"
pushed="$(skopeo inspect --format '{{.Digest}}' "docker://$repository@$digest")"
[ "$pushed" = "$digest" ] || { echo "push-image: the registry serves $pushed, not $digest" >&2; exit 1; }
echo "pushed $repository:$version as $digest"
