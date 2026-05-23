#!/bin/sh
set -e

VERSION=${1?version required}
SRC_DIR=$(readlink -f "${2?source directory required}")
POOL_DIR=$(readlink -f "${3?pool directory required}")
CODENAME=${4?codename required}
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_ROOT=$(readlink -f "$SCRIPT_DIR/../../..")
# Replace - with ~ since - delimits the Debian revision in version strings.
VERSION_NO_V=$(echo "${VERSION#v}" | sed 's/-/~/g')
VERSION_NO_V="${VERSION_NO_V}~ppa$(date -u +%Y%m%d%H%M)"

. "$REPO_ROOT/scripts/build-env.sh"
export DEBEMAIL DEBFULLNAME

# Compile lldap
. "$HOME/.cargo/env"
cd "$SRC_DIR"
./app/build.sh
while IFS= read -r f; do wget -P app/static "$f"; done < app/static/libraries.txt
while IFS= read -r f; do wget -P app/static/fonts "$f"; done < app/static/fonts/fonts.txt
cargo build --release \
  --package lldap \
  --package lldap_migration_tool \
  --package lldap_set_password

cp -r "$SCRIPT_DIR/files/debian" "$SRC_DIR/debian"

dch --newversion "$VERSION_NO_V" \
      --distribution "$CODENAME" \
      "Automated build of lldap $VERSION."

dpkg-buildpackage -b --no-sign

mkdir -p "$POOL_DIR"
mv "$(dirname "$SRC_DIR")"/*.deb "$POOL_DIR/"
