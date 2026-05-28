#!/bin/sh
# Source this script to set RUST_TARGET and CARGO_TARGET_*_LINKER based on
# DEB_HOST_ARCH. No-op when not cross-compiling.
#
# Cargo cannot auto-discover cross-linkers because the GNU triple
# (e.g. aarch64-linux-gnu) differs from the Rust target triple
# (e.g. aarch64-unknown-linux-gnu). We export the linker explicitly so any
# package that sources this script gets correct cross-compilation for free.

BUILD_ARCH=$(dpkg --print-architecture)
HOST_ARCH=${DEB_HOST_ARCH:-$BUILD_ARCH}
export RUST_TARGET=""
if [ "$HOST_ARCH" != "$BUILD_ARCH" ]; then
  case "$HOST_ARCH" in
    amd64)
      RUST_TARGET="x86_64-unknown-linux-gnu"
      export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="x86_64-linux-gnu-gcc"
      ;;
    arm64)
      RUST_TARGET="aarch64-unknown-linux-gnu"
      export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="aarch64-linux-gnu-gcc"
      ;;
    armhf)
      RUST_TARGET="armv7-unknown-linux-gnueabihf"
      export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER="arm-linux-gnueabihf-gcc"
      ;;
    armel)
      RUST_TARGET="arm-unknown-linux-gnueabi"
      export CARGO_TARGET_ARM_UNKNOWN_LINUX_GNUEABI_LINKER="arm-linux-gnueabi-gcc"
      ;;
    i386)
      RUST_TARGET="i686-unknown-linux-gnu"
      export CARGO_TARGET_I686_UNKNOWN_LINUX_GNU_LINKER="i686-linux-gnu-gcc"
      ;;
    ppc64el)
      RUST_TARGET="powerpc64le-unknown-linux-gnu"
      export CARGO_TARGET_POWERPC64LE_UNKNOWN_LINUX_GNU_LINKER="powerpc64le-linux-gnu-gcc"
      ;;
    riscv64)
      RUST_TARGET="riscv64gc-unknown-linux-gnu"
      export CARGO_TARGET_RISCV64GC_UNKNOWN_LINUX_GNU_LINKER="riscv64-linux-gnu-gcc"
      ;;
    s390x)
      RUST_TARGET="s390x-unknown-linux-gnu"
      export CARGO_TARGET_S390X_UNKNOWN_LINUX_GNU_LINKER="s390x-linux-gnu-gcc"
      ;;
    *) echo "Unsupported Rust cross-compilation target: $HOST_ARCH" >&2; exit 1 ;;
  esac
fi
