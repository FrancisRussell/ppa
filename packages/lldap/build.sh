#!/bin/sh
set -e

VERSION=${1?version required}
SRC_DIR=${2?source directory required}
POOL_DIR=${3?pool directory required}
ARCH=${4?arch required}
VERSION_NO_V="${VERSION#v}~ppa1"
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PKG_DIR=$(mktemp -d)

trap 'rm -rf "$PKG_DIR"' EXIT

install -d "$PKG_DIR/usr/bin"
install -d "$PKG_DIR/usr/share/lldap/app/pkg"
install -d "$PKG_DIR/usr/share/lldap/app/static/fonts"
install -d "$PKG_DIR/etc/lldap"
install -d "$PKG_DIR/lib/systemd/system"
install -d "$PKG_DIR/DEBIAN"

install -m 755 "$SRC_DIR/target/release/lldap"                "$PKG_DIR/usr/bin/lldap"
install -m 755 "$SRC_DIR/target/release/lldap_migration_tool" "$PKG_DIR/usr/bin/lldap_migration_tool"
install -m 755 "$SRC_DIR/target/release/lldap_set_password"   "$PKG_DIR/usr/bin/lldap_set_password"

install -m 644 "$SRC_DIR/app/index.html" "$PKG_DIR/usr/share/lldap/app/index.html"
cp -r "$SRC_DIR/app/pkg/."    "$PKG_DIR/usr/share/lldap/app/pkg/"
cp -r "$SRC_DIR/app/static/." "$PKG_DIR/usr/share/lldap/app/static/"

install -m 640 "$SCRIPT_DIR/lldap_config.toml.default" "$PKG_DIR/etc/lldap/lldap_config.toml"
install -m 644 "$SCRIPT_DIR/lldap.service" "$PKG_DIR/lib/systemd/system/lldap.service"

sed -e "s/VERSION_PLACEHOLDER/$VERSION_NO_V/" \
    -e "s/ARCH_PLACEHOLDER/$ARCH/" \
    "$SCRIPT_DIR/DEBIAN/control.tmpl" > "$PKG_DIR/DEBIAN/control"
install -m 755 "$SCRIPT_DIR/DEBIAN/postinst" "$PKG_DIR/DEBIAN/postinst"
install -m 755 "$SCRIPT_DIR/DEBIAN/prerm"    "$PKG_DIR/DEBIAN/prerm"
install -m 644 "$SCRIPT_DIR/DEBIAN/conffiles" "$PKG_DIR/DEBIAN/conffiles"

mkdir -p "$POOL_DIR"
dpkg-deb --build --root-owner-group "$PKG_DIR" "$POOL_DIR/lldap_${VERSION_NO_V}_${ARCH}.deb"
