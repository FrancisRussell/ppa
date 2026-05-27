#!/bin/sh
set -e

VERSION=${1?version required}
SRC_DIR=$(readlink -f "${2?source directory required}")
POOL_DIR=$(readlink -f "${3?pool directory required}")
CODENAME=${4?codename required}
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_ROOT=$(readlink -f "$SCRIPT_DIR/../../..")

. "$REPO_ROOT/scripts/rust-cross-env.sh"

# Compile lldap
. "$HOME/.cargo/env"
cd "$SRC_DIR"
./app/build.sh
while IFS= read -r f; do wget -P app/static "$f"; done < app/static/libraries.txt
while IFS= read -r f; do wget -P app/static/fonts "$f"; done < app/static/fonts/fonts.txt
# shellcheck disable=SC2086
cargo build --release \
  ${RUST_TARGET:+--target "$RUST_TARGET"} \
  --package lldap \
  --package lldap_migration_tool \
  --package lldap_set_password

# debian/rules expects binaries in target/release/; symlink the cross-compiled output.
[ -n "$RUST_TARGET" ] && ln -sf "$RUST_TARGET/release" target/release

cp -r "$SCRIPT_DIR/files/debian/." "$SRC_DIR/debian/"

"$REPO_ROOT/scripts/build-deb.sh" \
  lldap "$VERSION" "$SRC_DIR" "$POOL_DIR" "$CODENAME"
