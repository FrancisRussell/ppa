#!/bin/sh
set -e

echo "$APT_SIGNING_KEY" | gpg --import

cd docs

mkdir -p dists/trixie/main/binary-amd64

dpkg-scanpackages --multiversion pool/main \
  > dists/trixie/main/binary-amd64/Packages
gzip -kf dists/trixie/main/binary-amd64/Packages

cd dists/trixie
apt-ftparchive -c ../../../aptftp.conf release . > Release
gpg --batch --yes --clearsign -o InRelease Release
gpg --batch --yes -abs -o Release.gpg Release
