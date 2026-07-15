#!/bin/bash
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
# Environment:
#   DEB_HOST_ARCH   If set and differs from the native architecture,
#                   cross-compile for that architecture.
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
# Use the recipe commit timestamp for the ppa suffix so all arch builds of the
# same recipe state get an identical version string. Fall back to wall-clock if
# PPA_TIMESTAMP is unset (e.g. local builds).
if [ -n "$PPA_TIMESTAMP" ]; then
  PPA_DATE=$(date -u -d "@$PPA_TIMESTAMP" +%Y%m%d%H%M)
else
  PPA_DATE=$(date -u +%Y%m%d%H%M)
fi
if [ -n "$EPOCH" ]; then
  VERSION_PKG="${EPOCH}:${UPSTREAM_VERSION}-ppa${PPA_DATE}"
else
  VERSION_PKG="${UPSTREAM_VERSION}-ppa${PPA_DATE}"
fi

BUILD_ARCH=$(dpkg --print-architecture)
HOST_ARCH=${DEB_HOST_ARCH:-$BUILD_ARCH}
CROSS_FLAG=()
if [ "$HOST_ARCH" != "$BUILD_ARCH" ]; then
  CROSS_FLAG=(--host-arch "$HOST_ARCH")
fi

sudo mk-build-deps --install --remove \
  --tool 'apt-get -y --no-install-recommends' \
  "${CROSS_FLAG[@]}" \
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
  dpkg-buildpackage --no-sign "${CROSS_FLAG[@]}"
else
  dpkg-buildpackage -b --no-sign "${CROSS_FLAG[@]}"
fi

while IFS= read -r deb; do
  "$SCRIPT_DIR/check-deb-arch.sh" "$deb"
done < <(find "$(dirname "$SRC_DIR")" -maxdepth 1 -name "*.deb")
mkdir -p "$POOL_DIR"
find "$(dirname "$SRC_DIR")" -maxdepth 1 \
  \( -name "*.deb" -o -name "*.dsc" -o -name "*.tar.*" \) \
  -exec mv {} "$POOL_DIR/" \;
