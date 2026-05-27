#!/bin/sh
set -e

VERSION=${1?version required}
SRC_DIR=$(readlink -f "${2?source directory required}")
POOL_DIR=$(readlink -f "${3?pool directory required}")
CODENAME=${4?codename required}
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_ROOT=$(readlink -f "$SCRIPT_DIR/../../..")

# Go provides its own hardening; dpkg's ELF linker flags are incompatible with Go's linker.
export DEB_BUILD_MAINT_OPTIONS=hardening=-all

cp -r "$SCRIPT_DIR/files/debian/." "$SRC_DIR/debian/"
cp "$SCRIPT_DIR/files/forgejo.service" "$SRC_DIR/forgejo.service"
cp "$SCRIPT_DIR/files/app.ini" "$SRC_DIR/app.ini"

"$REPO_ROOT/scripts/build-deb.sh" \
  forgejo "$VERSION" "$SRC_DIR" "$POOL_DIR" "$CODENAME"
