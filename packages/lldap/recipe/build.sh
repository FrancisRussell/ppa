#!/bin/sh
set -e

VERSION=${1?version required}
SRC_DIR=$(readlink -f "${2?source directory required}")
POOL_DIR=$(readlink -f "${3?pool directory required}")
CODENAME=${4?codename required}
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_ROOT=$(readlink -f "$SCRIPT_DIR/../../..")

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

cp -r "$SCRIPT_DIR/files/debian/." "$SRC_DIR/debian/"

"$REPO_ROOT/scripts/build-deb.sh" \
  lldap "$VERSION" "$SRC_DIR" "$POOL_DIR" "$CODENAME"
