#!/bin/bash
set -e

VERSION=${1?version required}
SRC_DIR=$(readlink -f "${2?source directory required}")
POOL_DIR=$(readlink -f "${3?pool directory required}")
CODENAME=${4?codename required}
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_ROOT=$(readlink -f "$SCRIPT_DIR/../../..")

# tinymce, tinymce-langs and openpgp have no Debian package (unlike the other
# bundled JS libraries, which debian/roundcube-core.links symlinks in from
# real system packages), so this PPA fetches them here instead of via
# Debian's gbp import-orig --uscan secondary-tarball mechanism. Versions,
# URLs and sha1s are taken from upstream's own jsdeps.json at this commit.
TINYMCE_VERSION=5.10.9
TINYMCE_URL="https://download.tiny.cloud/tinymce/community/tinymce_${TINYMCE_VERSION}.zip"
TINYMCE_SHA1=ea53c43cc4cf932d9fb88dbb66e4671f1e858951

TINYMCE_LANGS_URL="https://download.tiny.cloud/tinymce/community/languagepacks/5/langs.zip?v=${TINYMCE_VERSION}"

OPENPGP_VERSION=6.3.0
OPENPGP_URL="https://cdn.jsdelivr.net/npm/openpgp@${OPENPGP_VERSION}/dist/openpgp.min.js"
OPENPGP_SHA1=fcfc7c22633bd018b7793de050dbde9b0d284799

fetch_and_verify() {
  local url=$1 dest=$2 sha1=$3
  wget -q -O "$dest" "$url"
  if [ -n "$sha1" ]; then
    echo "$sha1  $dest" | sha1sum -c -
  fi
}

# dbconfig-common's debian/sql/<db>/<version> migrations (see
# debian/sqlupdate and PACKAGING-NOTES.md) only get applied on upgrade if a
# file actually exists for a given upstream schema change - a missing one
# doesn't fail the build, it just silently leaves pre-existing installs on
# the old schema. Fail the build instead: for each backend, find the highest
# upstream timestamp already captured anywhere in debian/sql/<mapped-db>/ (via
# its `system.roundcube-version` marker update - present in every migration
# file regardless of which comment convention Debian used when it was
# written) and check no upstream SQL/{mysql,postgres,sqlite}/<timestamp>.sql
# at the pinned commit is newer than that.
check_sql_migrations() {
  local updb debdb f ts_num max
  declare -A dir_map=( [mysql]=mysql [postgres]=pgsql [sqlite]=sqlite3 )
  local -a missing=()

  for updb in "${!dir_map[@]}"; do
    debdb=${dir_map[$updb]}
    max=$(grep -ohrE "roundcube-version.\s*=\s*.[0-9]{8,}.|value.\s*=\s*.[0-9]{8,}.\s*WHERE\s+.?name.?\s*=\s*.roundcube-version" \
            "debian/sql/$debdb/" | grep -oE "[0-9]{8,}" | sort -n | tail -1)
    if [ -z "$max" ]; then
      echo "ERROR: could not determine captured schema version for debian/sql/$debdb/" >&2
      exit 1
    fi
    for f in "SQL/$updb"/*.sql; do
      [ -e "$f" ] || continue
      ts_num=$(basename "$f" .sql)
      [[ "$ts_num" =~ ^[0-9]+$ ]] || continue
      if [ "$ts_num" -gt "$max" ]; then
        missing+=("SQL/$updb/$ts_num.sql (captured max for $debdb: $max)")
      fi
    done
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "ERROR: upstream schema migration(s) not captured in debian/sql/ -" \
      "dbconfig-common upgrades would silently skip them:" >&2
    printf '  %s\n' "${missing[@]}" >&2
    echo "Add a new debian/sql/{mysql,pgsql,sqlite3}/<version> migration" \
      "(see debian/sqlupdate and PACKAGING-NOTES.md) before bumping the pin." >&2
    exit 1
  fi
}

cd "$SRC_DIR"

cp -r "$SCRIPT_DIR/files/debian/." "$SRC_DIR/debian/"
check_sql_migrations

# debian/rules expects these at the same top-level component directories
# Debian's own multi-component orig tarball would place them at.
fetch_and_verify "$TINYMCE_URL" tinymce.zip "$TINYMCE_SHA1"
unzip -q tinymce.zip
rm tinymce.zip

fetch_and_verify "$TINYMCE_LANGS_URL" tinymce-langs.zip ""
mkdir tinymce-langs
unzip -q -j tinymce-langs.zip -d tinymce-langs
rm tinymce-langs.zip

fetch_and_verify "$OPENPGP_URL" plugins/enigma/openpgp.min.js "$OPENPGP_SHA1"

# The files fetched above aren't part of the .orig.tar.gz (git archive only
# sees committed content), so dpkg-source treats them as source-package-local
# changes and needs to represent that as a diff - which fails for a binary
# file. Scanned rather than hardcoded so a future TinyMCE bump that adds,
# removes or renames a binary asset doesn't silently stop being covered.
find tinymce tinymce-langs plugins/enigma/openpgp.min.js -type f \
  -exec sh -c 'grep -Iq . "$1" || echo "$1"' _ {} \; \
  > debian/source/include-binaries

"$REPO_ROOT/scripts/build-deb.sh" \
  roundcube "$VERSION" "$SRC_DIR" "$POOL_DIR" "$CODENAME"
