#!/usr/bin/env bash
# Promote an uploaded and tag-verified prerelease to latest. If the stable Pages
# route fails after promotion, demote it and restore the previous latest.
set -euo pipefail

tag=${1:?usage: promote_release.sh TAG PREVIOUS_LATEST_TAG}
previous=${2:-}
version=${tag#v}
root=$(cd "$(dirname "$0")/.." && pwd)

if gh release edit "$tag" --draft=false --prerelease=false --latest=true \
    && LIVE_REQUIRE_RELEASE=1 LIVE_EXPECTED_VERSION="$version" "$root/tools/live" site; then
  exit 0
fi

echo "release $tag failed its live promotion check; restoring the previous stable release" >&2
rollback_ok=1
gh release edit "$tag" --prerelease=true --latest=false || rollback_ok=0
if [[ -n $previous ]]; then
  gh release edit "$previous" --latest=true || rollback_ok=0
fi

if [[ $rollback_ok == 1 ]]; then
  if [[ -n $previous ]]; then
    LIVE_REQUIRE_RELEASE=1 LIVE_EXPECTED_VERSION="${previous#v}" "$root/tools/live" site || rollback_ok=0
  else
    LIVE_REQUIRE_RELEASE=0 LIVE_EXPECTED_VERSION= "$root/tools/live" site || rollback_ok=0
  fi
fi

if [[ $rollback_ok != 1 ]]; then
  echo "error: automatic release rollback could not be verified" >&2
else
  echo "rollback verified; $tag is a prerelease and ${previous:-no prior release} is latest" >&2
fi
exit 1
