#!/bin/sh
set -e

VERSION=${1?version required}
SRC_DIR=$(readlink -f "${2?source directory required}")
POOL_DIR=$(readlink -f "${3?pool directory required}")
CODENAME=${4?codename required}
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
VERSION_NO_V="${VERSION#v}~ppa$(date -u +%Y%m%d%H%M)"

cp -r "$SCRIPT_DIR/files/debian" "$SRC_DIR/debian"

cd "$SRC_DIR"

DEBEMAIL="francis+ppa@unchartedbackwaters.co.uk" DEBFULLNAME="Francis Russell" \
  dch --newversion "$VERSION_NO_V" \
      --distribution "$CODENAME" \
      "Automated build of lldap $VERSION."

dpkg-buildpackage -b --no-sign

mkdir -p "$POOL_DIR"
mv "$(dirname "$SRC_DIR")"/*.deb "$POOL_DIR/"
