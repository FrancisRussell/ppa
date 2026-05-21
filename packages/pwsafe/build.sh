#!/bin/sh
set -e

VERSION=$1
SRC_DIR=$(readlink -f "$2")
POOL_DIR=$(readlink -f "$3")
CODENAME=$4
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
VERSION_PKG="${VERSION}~ppa1"

# Install our debian/ into the source tree
mkdir -p "$SRC_DIR/debian"
cp "$SCRIPT_DIR/debian/control"   "$SRC_DIR/debian/control"
cp "$SCRIPT_DIR/debian/rules"     "$SRC_DIR/debian/rules"
cp "$SCRIPT_DIR/debian/copyright" "$SRC_DIR/debian/copyright"
cp "$SCRIPT_DIR/debian/changelog" "$SRC_DIR/debian/changelog"

cd "$SRC_DIR"

# Prepend a new entry for this build
DEBEMAIL="francis+ppa@unchartedbackwaters.co.uk" DEBFULLNAME="Francis Russell" \
  dch --newversion "$VERSION_PKG" \
      --distribution "$CODENAME" \
      "Automated build from nsd20463/pwsafe master."

dpkg-buildpackage -b --no-sign

mkdir -p "$POOL_DIR"
mv "$(dirname "$SRC_DIR")"/*.deb "$POOL_DIR/"
