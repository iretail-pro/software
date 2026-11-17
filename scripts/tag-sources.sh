#!/usr/bin/env bash
# Tags every source repository of a published release on the commit the
# release was built from: v<version>, an annotated tag. The list is the
# release's own sources.txt, one "<repository> <commit>" a line (the
# repository without its owner, iretail-pro).
#
#   scripts/tag-sources.sh <version> <sources.txt>
#
# Environment: GH_TOKEN, a token with Contents: read and write on those
# repositories (IRETAIL_SOURCES_TOKEN). Needs gh.
#
# A commit main does not hold is refused; a tag already on the same commit
# is left as it is; a tag on another commit is never moved. Every line is
# tried, and the script fails at the end if any was refused.
set -euo pipefail
version="${1:?usage: tag-sources.sh <version> <sources.txt>}"
list="${2:?sources.txt}"
: "${GH_TOKEN:?GH_TOKEN is required to tag}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9a-z.-]+)?$ ]] || { echo "tag-sources: $version is not a version" >&2; exit 1; }
tag="v$version"
failed=0

tag_one() {
  local repo="$1" commit="$2" api status have type sha object
  api="repos/iretail-pro/$repo"
  status="$(gh api "$api/compare/$commit...main" --jq .status)" || return 1
  case "$status" in
    ahead|identical) ;;
    *) echo "tag-sources: $repo $commit is not on main ($status)" >&2; return 1 ;;
  esac
  if have="$(gh api "$api/git/ref/tags/$tag" --jq '[.object.type, .object.sha] | join(" ")' 2>/dev/null)"; then
    read -r type sha <<<"$have"
    if [ "$type" = tag ]; then sha="$(gh api "$api/git/tags/$sha" --jq .object.sha)"; fi
    [ "$sha" = "$commit" ] || { echo "tag-sources: $repo $tag is $sha already, not $commit" >&2; return 1; }
    echo "$repo $tag = $commit (already)"
    return 0
  fi
  object="$(gh api -X POST "$api/git/tags" -f tag="$tag" -f message="iRetail PRO $version" \
    -f object="$commit" -f type=commit --jq .sha)" || return 1
  gh api -X POST "$api/git/refs" -f ref="refs/tags/$tag" -f sha="$object" >/dev/null || return 1
  echo "$repo $tag = $commit"
}

while read -r repo commit rest; do
  [ -n "${repo:-}" ] || continue
  case "$repo" in \#*) continue ;; esac
  if ! [[ "$repo" =~ ^[a-z0-9][a-z0-9-]*$ && "$commit" =~ ^[0-9a-f]{40}$ && -z "${rest:-}" ]]; then
    echo "tag-sources: not a \"<repository> <commit>\" line: $repo $commit $rest" >&2
    failed=1
    continue
  fi
  tag_one "$repo" "$commit" || failed=1
done < "$list"
exit "$failed"
