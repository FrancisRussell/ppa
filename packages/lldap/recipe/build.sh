#!/bin/bash
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
# lldap pins a toolchain in rust-toolchain.toml; cargo uses that toolchain
# rather than the default, so we must add the cross target to it explicitly.
[ -n "$RUST_TARGET" ] && rustup target add "$RUST_TARGET"
./app/build.sh
while IFS= read -r f; do wget -P app/static "$f"; done < app/static/libraries.txt
while IFS= read -r f; do wget -P app/static/fonts "$f"; done < app/static/fonts/fonts.txt
CARGO_ARGS=()
[ -n "$RUST_TARGET" ] && CARGO_ARGS+=(--target "$RUST_TARGET")
cargo build --release \
  "${CARGO_ARGS[@]}" \
  --package lldap \
  --package lldap_migration_tool \
  --package lldap_set_password

# debian/rules expects binaries in target/release/; symlink the cross-compiled output.
# Remove target/release first: cargo creates it as a directory even for --target builds,
# and ln -sf into an existing directory would place the symlink inside it.
if [ -n "$RUST_TARGET" ]; then
  rm -rf target/release
  ln -sf "$RUST_TARGET/release" target/release
fi

cp -r "$SCRIPT_DIR/files/debian/." "$SRC_DIR/debian/"

"$REPO_ROOT/scripts/build-deb.sh" \
  lldap "$VERSION" "$SRC_DIR" "$POOL_DIR" "$CODENAME"
