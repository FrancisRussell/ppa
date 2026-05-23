#!/bin/sh
set -e

REPO_ROOT=$(readlink -f "${1?repo root required}")
ARCH=${2?arch required}

echo "$APT_SIGNING_KEY" | gpg --import

cd "$REPO_ROOT"

conf=$(mktemp)
trap 'rm -f "$conf"' EXIT

for codename_dir in pool/*/; do
  [ -d "$codename_dir" ] || continue
  codename=$(basename "$codename_dir")
  [ -d "pool/$codename/main" ] || continue

  mkdir -p "dists/$codename/main/binary-$ARCH"
  mkdir -p "dists/$codename/main/source"

  dpkg-scanpackages --multiversion "pool/$codename/main" \
    > "dists/$codename/main/binary-$ARCH/Packages"
  gzip -kf "dists/$codename/main/binary-$ARCH/Packages"

  dpkg-scansources "pool/$codename/main" \
    > "dists/$codename/main/source/Sources"
  gzip -kf "dists/$codename/main/source/Sources"

  cat > "$conf" <<EOF
APT::FTPArchive::Release {
  Origin "$GITHUB_REPOSITORY_OWNER";
  Label "$GITHUB_REPOSITORY";
  Suite "$codename";
  Codename "$codename";
  Architectures "$ARCH";
  Components "main";
};
EOF

  apt-ftparchive -c "$conf" release "dists/$codename" > "dists/$codename/Release"
  gpg --batch --yes --clearsign -o "dists/$codename/InRelease" "dists/$codename/Release"
  gpg --batch --yes -abs -o "dists/$codename/Release.gpg" "dists/$codename/Release"
done
