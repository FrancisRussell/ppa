#!/bin/sh
set -e

CHECKOUT_DIR=$(readlink -f "${1?checkout directory required}")
DATE=$(git -C "$CHECKOUT_DIR" log -1 --format=%cI | cut -c1-10 | tr -d -)

if [ -z "$DATE" ]; then
  echo "Failed to read committer date from $CHECKOUT_DIR" >&2
  exit 1
fi

echo "2.01+git${DATE}"
