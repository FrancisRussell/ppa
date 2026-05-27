#!/bin/sh
# Produces a Debian version string from the tag pointing at HEAD in a checkout.
# Usage: get-version.sh <checkout-dir>
set -e

CHECKOUT_DIR=$(readlink -f "${1?checkout directory required}")
TAG=$(git -C "$CHECKOUT_DIR" tag --points-at HEAD \
  | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V | tail -n1)

if [ -z "$TAG" ]; then
  echo "No tag found pointing at HEAD in $CHECKOUT_DIR" >&2
  exit 1
fi

echo "${TAG#v}"
