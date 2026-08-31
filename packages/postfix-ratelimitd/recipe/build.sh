#!/bin/bash
set -e

VERSION=${1?version required}
SRC_DIR=$(readlink -f "${2?source directory required}")
POOL_DIR=$(readlink -f "${3?pool directory required}")
CODENAME=${4?codename required}
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_ROOT=$(readlink -f "$SCRIPT_DIR/../../..")

. "$HOME/.cargo/env"

cd "$SRC_DIR"
cargo build --release

cp -r "$SCRIPT_DIR/files/debian/." "$SRC_DIR/debian/"

"$REPO_ROOT/scripts/build-deb.sh" \
  postfix-ratelimitd "$VERSION" "$SRC_DIR" "$POOL_DIR" "$CODENAME"
