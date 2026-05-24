#!/bin/sh
# Tags use an fsv- prefix (e.g. fsv-3.0) rather than the conventional v prefix.
set -e

SRC_DIR=$(readlink -f "${1?source directory required}")
TAG=$(git -C "$SRC_DIR" tag --points-at HEAD \
  | grep -E '^(v|fsv-)[0-9]+\.[0-9]+(\.[0-9]+)?$' \
  | sort -V | tail -n1)

if [ -z "$TAG" ]; then
  echo "No version tag found at HEAD in $SRC_DIR" >&2
  exit 1
fi

echo "$TAG" | sed 's/^v//; s/^fsv-//'
