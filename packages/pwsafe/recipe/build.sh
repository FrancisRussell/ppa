#!/bin/sh
set -e

VERSION=${1?version required}
SRC_DIR=$(readlink -f "${2?source directory required}")
POOL_DIR=$(readlink -f "${3?pool directory required}")
CODENAME=${4?codename required}
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_ROOT=$(readlink -f "$SCRIPT_DIR/../../..")
# Replace - with ~ since - delimits the Debian revision in version strings.
UPSTREAM_VERSION=$(echo "$VERSION" | sed 's/-/~/g')
VERSION_PKG="${UPSTREAM_VERSION}-ppa$(date -u +%Y%m%d%H%M)"

. "$REPO_ROOT/scripts/build-env.sh"
export DEBEMAIL DEBFULLNAME

# Create orig tarball before injecting debian/
git -C "$SRC_DIR" archive \
  --prefix="pwsafe-${UPSTREAM_VERSION}/" \
  HEAD | gzip > "$(dirname "$SRC_DIR")/pwsafe_${UPSTREAM_VERSION}.orig.tar.gz"

# Install our debian/ into the source tree
mkdir -p "$SRC_DIR/debian/source"
cp "$SCRIPT_DIR/files/debian/control"        "$SRC_DIR/debian/control"
cp "$SCRIPT_DIR/files/debian/rules"          "$SRC_DIR/debian/rules"
cp "$SCRIPT_DIR/files/debian/copyright"      "$SRC_DIR/debian/copyright"
cp "$SCRIPT_DIR/files/debian/changelog"      "$SRC_DIR/debian/changelog"
cp "$SCRIPT_DIR/files/debian/source/format"  "$SRC_DIR/debian/source/format"

cd "$SRC_DIR"

mk-build-deps --install --remove \
  --tool 'apt-get -y --no-install-recommends' \
  "$SCRIPT_DIR/files/debian/control"

COMMIT=$(git rev-parse HEAD)

# Prepend a new entry for this build
dch --newversion "$VERSION_PKG" \
      --distribution "$CODENAME" \
      "Automated build from nsd20463/pwsafe commit $COMMIT."

dpkg-buildpackage --no-sign

mkdir -p "$POOL_DIR"
find "$(dirname "$SRC_DIR")" -maxdepth 1 \
  \( -name "*.deb" -o -name "*.dsc" -o -name "*.tar.*" \) \
  -exec mv {} "$POOL_DIR/" \;
