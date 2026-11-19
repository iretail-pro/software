#!/usr/bin/env bash
# Checks, before anything is built, that every source of a release is a
# commit its repository's main holds: the same rule scripts/tag-sources.sh
# applies once the release is out, so a commit it would refuse to tag (a
# vendored core or design from a branch that never merged, say) stops the
# run here instead of after publishing.
#
#   scripts/check-sources.sh <sources.txt>
#
# One "<repository> <commit>" a line (the repository without its owner,
# iretail-pro). Environment: GH_TOKEN, a token that reads those
# repositories (IRETAIL_SOURCES_TOKEN). Needs gh. Every line is tried, and
# the script fails at the end if any commit is not on main.
set -euo pipefail
list="${1:?usage: check-sources.sh <sources.txt>}"
: "${GH_TOKEN:?GH_TOKEN is required}"
failed=0
while read -r repo commit rest; do
  [ -n "${repo:-}" ] || continue
  if ! [[ "$repo" =~ ^[a-z0-9][a-z0-9-]*$ && "$commit" =~ ^[0-9a-f]{40}$ && -z "${rest:-}" ]]; then
    echo "check-sources: not a \"<repository> <commit>\" line: $repo $commit $rest" >&2
    failed=1
    continue
  fi
  if ! status="$(gh api "repos/iretail-pro/$repo/compare/$commit...main" --jq .status)"; then
    echo "check-sources: $repo $commit cannot be compared with main" >&2
    failed=1
    continue
  fi
  case "$status" in
    ahead|identical) echo "$repo $commit is on main" ;;
    *) echo "check-sources: $repo $commit is not on main ($status)" >&2; failed=1 ;;
  esac
done < "$list"
exit "$failed"
