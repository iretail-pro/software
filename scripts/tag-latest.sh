#!/usr/bin/env bash
# Points the tag `latest` of one image at a published release's digest, so
# `docker compose up` with deploy's defaults (`…:latest`) runs the newest
# release. The release's own tag <version> must already name that digest:
# `latest` only ever follows a version, it never names an image of its own.
#
#   scripts/tag-latest.sh <repository> <version> <digest>
#
# Environment: GH_TOKEN and GITHUB_ACTOR (ghcr.io). Needs skopeo.
set -euo pipefail
repository="${1:?usage: tag-latest.sh <repository> <version> <digest>}"
version="${2:?version}"
digest="${3:?digest}"
: "${GH_TOKEN:?GH_TOKEN is required to push}"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "tag-latest: $digest is not a digest" >&2; exit 1; }
skopeo login "${repository%%/*}" -u "${GITHUB_ACTOR:?GITHUB_ACTOR}" --password-stdin <<<"$GH_TOKEN" >/dev/null
have="$(skopeo inspect --format '{{.Digest}}' "docker://$repository:$version")"
[ "$have" = "$digest" ] || { echo "tag-latest: $repository:$version is $have, not $digest" >&2; exit 1; }
# A copy inside one repository moves no layer: it only writes the tag.
skopeo copy --all --preserve-digests "docker://$repository@$digest" "docker://$repository:latest"
now="$(skopeo inspect --format '{{.Digest}}' "docker://$repository:latest")"
[ "$now" = "$digest" ] || { echo "tag-latest: $repository:latest is $now, not $digest" >&2; exit 1; }
echo "$repository:latest = $digest ($version)"
