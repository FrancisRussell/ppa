#!/bin/sh
# Build a Debian package from a git checkout and deposit build artifacts into
# a pool directory. Expects SRC_DIR to already contain a debian/ directory.
# Handles build-dep installation, changelog stamping, and dpkg-buildpackage
# invocation. If debian/source/format exists, creates an orig tarball from the
# git checkout and does a source+binary build; otherwise binary-only.
#
# Usage: build-deb.sh [OPTIONS] PACKAGE VERSION SRC_DIR POOL_DIR CODENAME
#
# Options:
#   --epoch N   Prepend epoch N: to the Debian package version
#
# VERSION must be a Debian upstream version (no epoch, no v prefix). Hyphens are
# converted to tildes so they don't conflict with the Debian revision delimiter.
set -e

EPOCH=""

while [ $# -gt 0 ]; do
  case "$1" in
    --epoch) EPOCH="$2"; shift 2 ;;
    *) break ;;
  esac
done

PACKAGE=${1?package required}
VERSION=${2?version required}
SRC_DIR=$(readlink -f "${3?source directory required}")
POOL_DIR=$(readlink -f "${4?pool directory required}")
CODENAME=${5?codename required}
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

. "$SCRIPT_DIR/maintainer.sh"
export DEBEMAIL DEBFULLNAME

# Replace - with ~ since - delimits the Debian revision in version strings.
UPSTREAM_VERSION=$(echo "$VERSION" | sed 's/-/~/g')
if [ -n "$EPOCH" ]; then
  VERSION_PKG="${EPOCH}:${UPSTREAM_VERSION}-ppa$(date -u +%Y%m%d%H%M)"
else
  VERSION_PKG="${UPSTREAM_VERSION}-ppa$(date -u +%Y%m%d%H%M)"
fi

mk-build-deps --install --remove \
  --tool 'apt-get -y --no-install-recommends' \
  "$SRC_DIR/debian/control"

COMMIT=$(git -C "$SRC_DIR" rev-parse HEAD)
cd "$SRC_DIR"

dch --newversion "$VERSION_PKG" \
  --distribution "$CODENAME" \
  "Automated build of $PACKAGE from commit $COMMIT."

if [ -f "debian/source/format" ]; then
  git -C "$SRC_DIR" archive \
    --prefix="${PACKAGE}-${UPSTREAM_VERSION}/" \
    HEAD | gzip > "$(dirname "$SRC_DIR")/${PACKAGE}_${UPSTREAM_VERSION}.orig.tar.gz"
  dpkg-buildpackage --no-sign
else
  dpkg-buildpackage -b --no-sign
fi

mkdir -p "$POOL_DIR"
find "$(dirname "$SRC_DIR")" -maxdepth 1 \
  \( -name "*.deb" -o -name "*.dsc" -o -name "*.tar.*" \) \
  -exec mv {} "$POOL_DIR/" \;
