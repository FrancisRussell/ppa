#!/bin/sh
# Rebuilds the APT repository index and signs the Release files for all
# codenames found under the pool/ directory.
# Usage: update-repo.sh <repo-root> <arch>
set -e

REPO_ROOT=$(readlink -f "${1?repo root required}")
ARCH=${2?arch required}

if [ -n "$APT_SIGNING_KEY" ]; then
  echo "$APT_SIGNING_KEY" | gpg --import
fi

cd "$REPO_ROOT"

conf=$(mktemp)
trap 'rm -f "$conf"' EXIT

for codename_dir in pool/*/; do
  [ -d "$codename_dir" ] || continue
  codename=$(basename "$codename_dir")
  [ -d "pool/$codename/main" ] || continue

  mkdir -p "dists/$codename/main/binary-$ARCH"
  mkdir -p "dists/$codename/main/source"

  # Regenerate Packages for every arch dir already in dists, not just the
  # current job's. arch:all packages are shared across all arch Packages files:
  # if a concurrent job replaces an arch:all deb in the pool and we only
  # regenerate our own arch, the other arch's Packages entry will reference a
  # stale size/hash.
  ARCH_LIST=""
  for arch_dir in "dists/$codename/main"/binary-*/; do
    [ -d "$arch_dir" ] || continue
    existing_arch=$(basename "$arch_dir" | sed 's/^binary-//')
    ARCH_LIST="${ARCH_LIST:+$ARCH_LIST }$existing_arch"
    dpkg-scanpackages --multiversion --arch "$existing_arch" "pool/$codename/main" \
      > "$arch_dir/Packages"
    gzip -kf "$arch_dir/Packages"
  done

  dpkg-scansources "pool/$codename/main" \
    > "dists/$codename/main/source/Sources"
  gzip -kf "dists/$codename/main/source/Sources"

  cat > "$conf" <<EOF
APT::FTPArchive::Release {
  Origin "$GITHUB_REPOSITORY_OWNER";
  Label "$GITHUB_REPOSITORY";
  Suite "$codename";
  Codename "$codename";
  Architectures "$ARCH_LIST";
  Components "main";
};
EOF

  apt-ftparchive -c "$conf" release "dists/$codename" > "dists/$codename/Release"
  if [ -n "$APT_SIGNING_KEY" ]; then
    gpg --batch --yes --clearsign -o "dists/$codename/InRelease" "dists/$codename/Release"
    gpg --batch --yes -abs -o "dists/$codename/Release.gpg" "dists/$codename/Release"
  fi
done
