#!/bin/sh
# Resolves a package's source.yml to a specific git commit hash.
# Usage: resolve-source.sh <package>
# Outputs JSON: {repo, ref, commit}
# Requires GITHUB_TOKEN for latest_release resolution.
set -e

PACKAGE=${1?package required}
REPO_ROOT=$(readlink -f "$(dirname "$0")/..")
SOURCE_YML="$REPO_ROOT/packages/$PACKAGE/source.yml"

REPO=$(yq -r '.repo' "$SOURCE_YML")
PIN=$(yq -r '.pin // ""' "$SOURCE_YML")
TRACK=$(yq -r '.track // ""' "$SOURCE_YML")

if [ -n "$PIN" ]; then
  jq -n --arg repo "$REPO" --arg ref "$PIN" --arg commit "$PIN" \
    '{repo: $repo, ref: $ref, commit: $commit}'
elif [ "$TRACK" = "latest_release" ]; then
  REPO_PATH=$(echo "$REPO" | sed 's|https://github.com/||')
  TAG=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
    "https://api.github.com/repos/$REPO_PATH/releases/latest" \
    | jq -r '.tag_name')
  if [ -z "$TAG" ] || [ "$TAG" = "null" ]; then
    echo "Failed to fetch latest release for $REPO_PATH" >&2
    exit 1
  fi
  COMMIT=$(git ls-remote "$REPO" "refs/tags/$TAG" | cut -f1)
  if [ -z "$COMMIT" ]; then
    echo "Failed to resolve tag $TAG to a commit for $REPO" >&2
    exit 1
  fi
  jq -n --arg repo "$REPO" --arg ref "$TAG" --arg commit "$COMMIT" \
    '{repo: $repo, ref: $ref, commit: $commit}'
else
  echo "source.yml must specify either pin or track" >&2
  exit 1
fi
