#!/bin/sh
set -e

VERSION=${1?version required}
SRC_DIR=$(readlink -f "${2?source directory required}")
POOL_DIR=$(readlink -f "${3?pool directory required}")
CODENAME=${4?codename required}
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_ROOT=$(readlink -f "$SCRIPT_DIR/../../..")
VERSION_PKG="${VERSION}~ppa$(date -u +%Y%m%d%H%M)"

. "$REPO_ROOT/scripts/build-env.sh"
export DEBEMAIL DEBFULLNAME

# Install our debian/ into the source tree
mkdir -p "$SRC_DIR/debian"
cp "$SCRIPT_DIR/files/debian/control"   "$SRC_DIR/debian/control"
cp "$SCRIPT_DIR/files/debian/rules"     "$SRC_DIR/debian/rules"
cp "$SCRIPT_DIR/files/debian/copyright" "$SRC_DIR/debian/copyright"
cp "$SCRIPT_DIR/files/debian/changelog" "$SRC_DIR/debian/changelog"

cd "$SRC_DIR"

mk-build-deps --install --remove \
  --tool 'apt-get -y --no-install-recommends' \
  "$SCRIPT_DIR/files/debian/control"

COMMIT=$(git rev-parse HEAD)

# Prepend a new entry for this build
dch --newversion "$VERSION_PKG" --force-bad-version \
      --distribution "$CODENAME" \
      "Automated build from FrancisRussell/encspot commit $COMMIT."

dpkg-buildpackage -b --no-sign

mkdir -p "$POOL_DIR"
mv "$(dirname "$SRC_DIR")"/*.deb "$POOL_DIR/"
