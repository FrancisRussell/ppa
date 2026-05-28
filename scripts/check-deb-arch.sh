#!/bin/bash
# Verifies that all ELF binaries inside a .deb package were compiled for the
# architecture declared in the package metadata. Exits non-zero if any mismatch
# is found. Skips Architecture: all packages since they contain no arch-specific
# binaries.
#
# Usage: check-deb-arch.sh DEB
set -e

DEB=${1?deb file required}

if ! command -v readelf > /dev/null 2>&1; then
  echo "check-deb-arch: readelf not found (install binutils)" >&2
  exit 1
fi

DEB_ARCH=$(dpkg-deb --field "$DEB" Architecture)
if [ "$DEB_ARCH" = "all" ]; then
  exit 0
fi

case "$DEB_ARCH" in
  amd64)   ELF_MACHINE="Advanced Micro Devices X86-64" ;;
  arm64)   ELF_MACHINE="AArch64" ;;
  armhf)   ELF_MACHINE="ARM" ;;
  armel)   ELF_MACHINE="ARM" ;;
  i386)    ELF_MACHINE="Intel 80386" ;;
  ppc64el) ELF_MACHINE="PowerPC64" ;;
  riscv64) ELF_MACHINE="RISC-V" ;;
  s390x)   ELF_MACHINE="IBM S/390" ;;
  *) echo "check-deb-arch: unknown architecture: $DEB_ARCH" >&2; exit 1 ;;
esac

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
dpkg-deb --extract "$DEB" "$TMPDIR"

FAILED=0
while IFS= read -r f; do
  MACHINE=$(readelf -h "$f" 2>/dev/null | awk '/^[[:space:]]*Machine:/ { sub(/^[[:space:]]*Machine:[[:space:]]*/, ""); print; exit }')
  [ -z "$MACHINE" ] && continue
  REL=${f#"$TMPDIR"/}
  if [ "$MACHINE" != "$ELF_MACHINE" ]; then
    echo "check-deb-arch: $REL: expected $DEB_ARCH ($ELF_MACHINE), got $MACHINE" >&2
    FAILED=1
  else
    echo "check-deb-arch: $REL: ok ($DEB_ARCH)"
  fi
done < <(find "$TMPDIR" -type f)

[ "$FAILED" -eq 0 ]
