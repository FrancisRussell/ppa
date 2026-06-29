#!/bin/sh
# Source this script to set GOARCH, CC, CGO_ENABLED, and (for armel) GOARM based on DEB_HOST_ARCH.
# No-op when not cross-compiling.
#
# Go defaults CGO_ENABLED=0 for cross-compilation; we set it to 1 so packages
# that require CGO (e.g. SQLite via mattn/go-sqlite3) continue to work.
# CC is set explicitly because Go cannot auto-discover the cross-compiler.

BUILD_ARCH=$(dpkg --print-architecture)
HOST_ARCH=${DEB_HOST_ARCH:-$BUILD_ARCH}
if [ "$HOST_ARCH" != "$BUILD_ARCH" ]; then
  case "$HOST_ARCH" in
    amd64)
      export GOARCH="amd64"
      export CC="x86_64-linux-gnu-gcc"
      ;;
    arm64)
      export GOARCH="arm64"
      export CC="aarch64-linux-gnu-gcc"
      ;;
    armhf)
      export GOARCH="arm"
      export CC="arm-linux-gnueabihf-gcc"
      ;;
    armel)
      export GOARCH="arm"
      export GOARM="6"
      export CC="arm-linux-gnueabi-gcc"
      ;;
    i386)
      export GOARCH="386"
      export CC="i686-linux-gnu-gcc"
      ;;
    ppc64el)
      export GOARCH="ppc64le"
      export CC="powerpc64le-linux-gnu-gcc"
      ;;
    riscv64)
      export GOARCH="riscv64"
      export CC="riscv64-linux-gnu-gcc"
      ;;
    s390x)
      export GOARCH="s390x"
      export CC="s390x-linux-gnu-gcc"
      ;;
    *) echo "Unsupported Go cross-compilation target: $HOST_ARCH" >&2; exit 1 ;;
  esac
  export CGO_ENABLED=1
fi
