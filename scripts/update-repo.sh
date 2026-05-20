#!/bin/sh
set -e

REPO_ROOT=$1
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

echo "$APT_SIGNING_KEY" | gpg --import

cd "$REPO_ROOT"

mkdir -p dists/trixie/main/binary-amd64

dpkg-scanpackages --multiversion pool/main \
  > dists/trixie/main/binary-amd64/Packages
gzip -kf dists/trixie/main/binary-amd64/Packages

cd dists/trixie
apt-ftparchive -c "$SCRIPT_DIR/../aptftp.conf" release . > Release
gpg --batch --yes --clearsign -o InRelease Release
gpg --batch --yes -abs -o Release.gpg Release
