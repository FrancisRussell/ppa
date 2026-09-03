#!/bin/sh
# postfix-ratelimitd has no release tags yet; the upstream version is taken
# from Cargo.toml and combined with the commit date.
set -e

CHECKOUT_DIR=$(readlink -f "${1?checkout directory required}")
DATE=$(git -C "$CHECKOUT_DIR" log -1 --format=%cI | cut -c1-10 | tr -d -)

if [ -z "$DATE" ]; then
  echo "Failed to read committer date from $CHECKOUT_DIR" >&2
  exit 1
fi

echo "0.1.0+git${DATE}"
