#!/bin/sh
# Remove pool files not referenced by any build record for this package.
# Usage: gc-pool.sh <builds-pkg-dir> <pool-dir>
#   builds-pkg-dir: e.g. builds/noble/forgejo  (contains arch subdirs with *.json)
#   pool-dir:       e.g. pool/noble/main/f/forgejo
set -e

BUILDS_PKG_DIR=${1?builds package directory required}
POOL_DIR=${2?pool directory required}

[ -d "$POOL_DIR" ] || exit 0

referenced=$(mktemp)
trap 'rm -f "$referenced"' EXIT

if [ -d "$BUILDS_PKG_DIR" ]; then
  find "$BUILDS_PKG_DIR" -name '*.json' -exec jq -r '.output.files[]' {} \; \
    | sort -u > "$referenced"
fi

[ -s "$referenced" ] || { echo "gc-pool: no build records found in $BUILDS_PKG_DIR" >&2; exit 1; }

find "$POOL_DIR" -maxdepth 1 -type f | while IFS= read -r f; do
  fname=$(basename "$f")
  if ! grep -qxF "$fname" "$referenced"; then
    echo "gc-pool: removing unreferenced $fname"
    rm -f "$f"
  fi
done
