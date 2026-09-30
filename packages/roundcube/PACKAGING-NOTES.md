# Packaging notes: Roundcube 1.7

## Motivation

Debian doesn't package Roundcube 1.7 (`debian/latest` on salsa is 1.6.19).

## Sources

- Upstream: <https://github.com/roundcube/roundcubemail>, pinned (not
  tracked) via `source.yml` at tag `1.7.4`, commit
  `0d05c37a6e565b1ff0f3a4472081f20a64d569a1`. Pinned rather than
  `track: latest_release` because Roundcube maintains two concurrent release
  lines and `latest_release` can't express "stay on the 1.7.x line."
- Debian packaging base: <https://salsa.debian.org/roundcube-team/roundcube>,
  `debian/latest` branch (1.6.19+dfsg-1). `debian/` was bulk-copied from
  there; patches were rebased forward onto 1.7.4.

## What's changed against Debian's 1.6.x packaging

### Patch series (`debian/patches/`)

Most of salsa's patch series is upstream cherry-picks already merged into
1.7.4, so they're dropped. What's kept or added:

Ported forward unchanged: `dbconfig-common-support.patch`,
`debianize-config.patch`, `update-script.patch`,
`use-enchant.patch`, `default-charset-utf8.patch`,
`debianize-password-plugin.patch`,
`map-sqlite3-to-sqlite.patch` (Debian bug #714727),
`use-embedded-jquery-for-http-authentication.patch`,
`rename-python-to-python3.patch`, `use-system-JQueryUI.patch`.

Ported forward but hand-rebased against 1.7.4's actual code (upstream moved
on since whatever version the original Debian patch targeted):

- `fix-install-path.patch` - Debian's original patch (by Guilhem Moulin)
  hardcodes `INSTALL_PATH` to `/var/lib/roundcube/` across `bin/*.sh`,
  `installer/index.php`, `program/include/iniset.php`, and makes
  `tests/bootstrap.php` use the `RCUBE_INSTALL_PATH` environment
  variable instead. Extended this session to give
  `installer/index.php` the same `RCUBE_INSTALL_PATH` fallback:
  `tests/Public/InstallerTest.php` (added upstream after Debian's patch
  was written) spawns a PHP built-in server straight from the source
  tree and requests `installer.php`, which needs to find
  `program/include/iniset.php` there too, not at the hardcoded install
  location.
- `Avoid-dependency-on-new-package-mlocati-ip-lib.patch` (Debian bug
  #1131182) - avoids a dependency on `mlocati/ip-lib` (not packaged in
  Debian), introduced upstream to fix **CVE-2026-35540** (SSRF via
  obfuscated IP-literal parsing in `is_local_url()`). 1.7.4 has refactored
  `is_local_url()` to delegate range checks to a shared `is_ip_in_range()`
  helper (also used for `proxy_whitelist` checks against
  `$_SERVER['REMOTE_ADDR']`), so this patch removes the `IPLib\Factory`
  calls from that helper instead, doing CIDR matching by hand against
  `inet_pton()`. The obfuscation-resistant parsing itself (`inet_pton2()`)
  is unchanged from Debian's fix. Debian's own patch also added dedicated
  CVE-regression cases to `tests/Framework/UtilsTest.php`; that hunk is
  restored here (rebased onto the current PSR-4/attribute-based test
  structure) and extended with an IPv4-compatible-IPv6 case - see "Two
  separate test mechanisms" below.
- `update-composer-pear-package-names.patch` - renames `pear/*` requires to
  `pear-pear.php.net/*` (pkg-php-tools' PEAR-channel naming convention) and
  relaxes `~`/`^` version operators to `>=`, rewritten against 1.7.4's
  actual dependency list.
- `trim-jsdeps-to-unpackaged-libs.patch` - trims `jsdeps.json` to libraries
  this package doesn't source another way (see JS/CSS strategy below), so
  it can't silently drift from what's actually happening at build time.

New patches, not in Debian's 1.6.19 packaging at all:

- `lower-guzzle-crypt_gpg-floors-for-trixie.patch` - upstream requires
  `guzzlehttp/guzzle ^7.10.0` and `pear/crypt_gpg ~1.7.0`; trixie ships
  `php-guzzlehttp-guzzle` 7.9.2-0.1 and `php-crypt-gpg` 1.6.11-1, both below
  those floors. Judged safe **for the currently pinned commit only**: guzzle
  7.10.0's sole changelog entry is PHP 8.5 support (irrelevant on trixie's
  PHP 8.4), and crypt_gpg 1.7.0 only replaces an internal PEAR dependency
  (`console_commandline`) that enigma never references directly (grepped
  for `PinCliParameters`/`SimpleCliWrapper`/`Console_CommandLine` - no
  hits). See the release checklist below - this needs re-justifying at
  every version bump, and a bad re-justification fails silently (builds
  against a too-old library instead of erroring).
- `backport-php85-array-first-last.patch` - upstream requires
  `symfony/polyfill-php85`, not packaged anywhere in Debian (trixie, sid,
  or backports). Not a version-floor nicety - `array_first()`/`array_last()`
  (added to PHP itself in 8.5) are called at 30+ sites across `program/lib`
  and `program/include`. Rather than package the whole polyfill, the two
  functions actually used are reimplemented directly in
  `program/include/iniset.php` (the bootstrap shared by web and CLI entry
  points), ported verbatim from the polyfill's `Php85.php`, guarded by
  `function_exists()` and `PHP_VERSION_ID < 80500` so it becomes a no-op
  once trixie eventually ships PHP >= 8.5.
- `provide-tests-autoloader.patch`, `mark-qrcode-test-flaky.patch`,
  `drop-slow-test-detector-extension.patch` - enable `dh_auto_test`
  (disabled in Debian's own 1.6.19 packaging). See "Two separate test
  mechanisms" below for what each one does and why.

Ported forward but hand-rebased (structural change, not just content):

- `fix-autoload-locations.patch` (Debian bug #1040705) - restores a
  `stream_resolve_include_path()`/`include_once` guard in
  `program/actions/contacts/qrcode.php` and
  `program/include/rcmail_oauth.php`, needed because this build never
  runs `composer install` and so has no `vendor/autoload.php`; without
  it, `program/lib/Roundcube/bootstrap.php`'s generic `rcube_autoload()`
  is the only autoloader available, and it assumes a class's PHP
  namespace maps 1:1 onto the installed package's directory layout -
  true for `php-guzzlehttp-guzzle` but not for `php-bacon-qr-code`,
  which installs under an extra `Bacon/` prefix
  (`/usr/share/php/Bacon/BaconQrCode/...`). Without this patch the
  QR-code contact-export feature is silently unavailable on every
  install, on every architecture, regardless of `php-bacon-qr-code`
  being correctly declared and installed. Rebased only because upstream
  moved `qrcode.php`'s `use BaconQrCode\...` imports above the file's
  header comment block; the patch's own header explains the exact
  insertion-point change.

### `debian/control`

- `php-guzzlehttp-promises` and `php-league-commonmark` added to
  `Build-Depends` - real 1.7.4 composer requires salsa's 1.6.19-era control
  didn't have.
- `libjs-less` added to `roundcube-core`'s `Depends` - a gap in Debian's
  *own* control file (their `roundcube-core.links` symlinks
  `usr/share/javascript/less/less.min.js` but nothing in their `Depends`
  provides that path). `node-less` (also in `Build-Depends`) is a different
  package: the offline Node.js LESS *compiler* used to pre-build the
  elastic skin's CSS, not the client-side LESS.js library the browser
  loads.
- `debhelper-compat` lowered 14 -> 13, edited directly rather than via a
  patch: `recipe/build.sh` calls `mk-build-deps` against the raw
  `debian/control` *before* `dpkg-buildpackage` ever applies quilt patches,
  so a patch here would parse cleanly but never actually take effect at
  build-dep-install time. Any future fix to a `Build-Depends` line needs to
  go directly in this file for the same reason. trixie's debhelper
  (13.24.2) doesn't implement compat level 14 at all (absent from that
  version's own `debhelper-compat-upgrade-checklist(7)`; only exists in the
  trixie-backports debhelper, `14.5~bpo13+1`) - lowered to 13, which trixie
  fully supports, rather than depending on backports for a build-essential
  tool. Debhelper compat levels are safe to build at a lower, still-
  supported level, and `debian/rules` doesn't rely on any compat-14-specific
  default (it already calls `dh_installsystemd` explicitly rather than
  depending on a default-enable behavior for shipped units).
- `Maintainer` changed to this PPA's convention; `Uploaders`, `Vcs-Git`,
  `Vcs-Browser` dropped (no `Uploaders` field and no `Vcs-*` fields on other
  packages in this PPA either).

### JS/CSS dependency strategy

Debian's own packaging mixes three approaches for Roundcube's bundled
third-party JS; this package follows the same split, adding one new library
(`openpgp`, new in the enigma plugin since 1.7):

1. **Symlink to a real Debian package** (`debian/roundcube-core.links` +
   the `dh_link` override in `debian/rules`' `execute_after_dh_link`) for
   everything Debian actually packages: `libjs-jquery`, `libjs-jquery-ui`,
   `libjs-jquery-minicolors`, `libjs-bootstrap4`, `libjs-jstimezonedetect`,
   `libjs-codemirror`, `libjs-less`.
2. **Live-fetch at build time**, for libraries with no Debian package at
   all: `tinymce`, `tinymce-langs`, `openpgp` (OpenPGP.js). Debian's real
   packaging would source these via `gbp import-orig --uscan`'s
   multi-component secondary-tarball support; this PPA's build containers
   have network access (unlike Debian's actual buildds), so
   `recipe/build.sh` fetches them directly instead, verifying each against
   a recorded sha1. `debian/rules` expects these at the same top-level
   directories (`tinymce/js/tinymce/...`, `tinymce-langs/*.js`) Debian's
   own multi-component import would produce - confirmed against the real
   zip layouts: `tinymce_5.10.9.zip` contains a top-level `tinymce/` dir
   wrapping `js/tinymce/...`; `langs.zip` puts files under a `langs/`
   subdirectory, not flat at the root, so `recipe/build.sh` flattens that
   with `unzip -j`. Fetching directly rather than via a real secondary orig
   tarball also means these files aren't in the `.orig.tar.gz` dpkg-source
   diffs against, so any binary among them (currently just two
   `tinymce-mobile.woff` icon fonts) can't be represented as a diff at all -
   `recipe/build.sh` scans the fetched files for binaries and writes
   `debian/source/include-binaries` at build time rather than hardcoding
   that list, so a future TinyMCE bump that adds one doesn't silently break.
   The resulting source package is still fully valid and rebuildable
   (`dpkg-source -x` reconstructs the exact same tree, no network needed),
   just not idiomatic: Debian's real package keeps tinymce/tinymce-langs as
   clean separate orig components, where ours embeds them as one large
   Debian diff dominated by vendored JS. `debian/source/options` sets
   `single-debian-patch` for the same reason: without it, `dpkg-source -b`
   refuses by default to auto-generate a diff for upstream-file changes not
   captured by a named quilt patch (a deliberate safety check, separate
   from the binary-representability issue `include-binaries` solves), since
   these live-fetched files are exactly that from its point of view.
3. **Vendor tiny non-minified source directly** in
   `debian/missing-sources/publickey-0e011cb1.js`, matching Debian, for GPL
   source-availability compliance on the tiny bundled (minified)
   `publickey.js`.

### `debian/sql/` - dbconfig-common migrations

See "Mechanisms that are easy to miss" below for how this works.
`debian/sql/{mysql,pgsql,sqlite3}/1.7.4-1` was added: Debian's set (copied
from salsa) tops out at `1.6.1+dfsg-1`, capturing upstream's schema only
through timestamp `2022081200`. Upstream has two migrations beyond that
which Debian never packaged: `2022100100.sql` (adds an `uploads` table,
used by 1.7's chunked/drag-drop upload handling) and `2025092300.sql`
(renames `session.changed` to `session.expires_at`, with an index rename
and a data migration). `1.7.4-1` consolidates both, verbatim from
upstream's own SQL files, for all three backends. Named `1.7.4-1` (not
`-ppa...`) specifically so it sorts after any real Debian 1.6.x install and
before this package's own built version - verified with
`dpkg --compare-versions`.

### Binary package scope

Full parity with Debian's 6 binary packages: `roundcube-core`, `roundcube`,
`roundcube-mysql`, `roundcube-pgsql`, `roundcube-sqlite3`,
`roundcube-plugins` (includes the `managesieve`/sieve plugin).

### Build targets

`source.yml` declares two targets: trixie amd64 and resolute amd64. Noble is
excluded because its packaged PHP libraries are too old (see below). There is
no arm64 build because roundcube is `Architecture: all`, so a second
architecture would produce nothing new.

Every roundcube binary package is `Architecture: all` (pure PHP, no
compiled code), so there's nothing for a second architecture's build to
produce that the first one didn't already - `update-repo.sh` shares
`Architecture: all` packages across every arch's `Packages` index from
whichever arch directories already exist in the pool (created by this
PPA's other, genuinely architecture-specific packages), so arm64 clients
see this package without it ever being built there. Actually declaring an
arm64 target just adds an unnecessary cross-build (QEMU + `--host-arch`),
which also doesn't work cleanly for this package: `cleancss` and similar
build-time-only tools aren't annotated `:native` in Debian's own
`debian/control` either, so `mk-build-deps --host-arch arm64` tries to
resolve `cleancss:arm64`, which doesn't exist as a meaningful concept for
an arch:all Node.js tool. Debian's own buildds never hit this because they
build arm64 natively rather than cross-compiling.

Ubuntu noble's PHP composer-library versions are too old for 1.7.4's
actual `composer.json` floors even after the guzzle/crypt_gpg floor patch
above: `guzzlehttp/promises` needs `>=2.0` (noble has 1.5.3),
`guzzlehttp/guzzle` needs `>=7.9.2` (noble has 7.4.5), `league/commonmark`
needs `>=2.7` (noble has 2.4.2), `bacon/bacon-qr-code` needs `>=3.0.0`
(noble has 2.0.8). Accommodating noble would mean relaxing floors well
below what upstream actually tests against, which is more divergence-risk
than it's worth for a package this dependency-heavy.

### Deferred entirely

`debian/tests/*` (autopkgtest / DEP-8) is not addressed at all yet - see
"Two separate test mechanisms" below.

## Release checklist: bumping the pinned version

1. **Update `source.yml`'s `pin:`** to the new tag's commit, and
   `recipe/get-version.sh`'s hardcoded version string to match. Not
   automatic by design - see "Why the pin isn't auto-tracked" below. The
   version can't be derived from the checkout at build time: `pin:` means
   CI never fetches a tag ref (only `track: latest_release` packages get
   one), and upstream's own `RCMAIL_VERSION` constant tracks the branch
   (`1.7-git`), not the specific release.
2. **Diff salsa's `debian/patches/` directory listing against its
   `series`**, not just against what's in this package's `series` - a
   patch can be active in salsa's `series` without ever having been
   evaluated here. For each patch with a DEP-3 `Origin:` header, verify
   against the actual pinned-commit code before trusting the header alone
   to mean "already merged" - read the target file directly (or `git show
   <pin>:<path>`), don't just dry-run the patch with a lenient `patch`
   invocation: plain `patch -p1 --forward` accepts fuzzy/partial context
   matches that real `dpkg-source`'s quilt integration (fuzz=0) rejects, so
   a patch that's actually already merged can still look like it "applies
   cleanly" against the new code.
3. **Re-justify `lower-guzzle-crypt_gpg-floors-for-trixie.patch`**: check
   both projects' changelogs between the old and new pinned commit. A
   future Roundcube release could start calling APIs that only exist in
   the newer floors upstream declares; this patch would then silently
   build against a too-old library instead of failing loudly.
4. **Re-check the `debhelper-compat (= 13)` override in `debian/control`**
   is still needed - trixie may ship a newer debhelper by the time of the
   bump. This is a direct edit, not a patch (see `debian/control` below for
   why), so it survives a fresh salsa diff silently if forgotten.
5. **Diff upstream's already-captured `SQL/{mysql,postgres,sqlite}/`
   files** (everything at or below `2025092300`) against the newly pinned
   tag, not just look for new ones - if upstream retroactively fixed a bug
   in an already-shipped migration script, a version-string-only diff
   would miss it silently.
6. **Add a new `debian/sql/{mysql,pgsql,sqlite3}/<new-version>-1`
   migration** for any upstream schema files newer than what's already
   captured (currently `2025092300`). `recipe/build.sh`'s
   `check_sql_migrations()` enforces this at build time and fails loudly
   if it's missed - see below - but the composition of that file (which
   migrations to bundle, how to name it) is still a manual step.
7. **Re-verify the JS live-fetch versions/URLs/hashes** in
   `recipe/build.sh` (`TINYMCE_VERSION`, `TINYMCE_SHA1`, `OPENPGP_VERSION`,
   `OPENPGP_SHA1`) against the new tag's `jsdeps.json`.
8. **Re-verify the noble-exclusion reasoning** in `source.yml` still holds
   - re-check the composer floors above against noble's current package
   versions in case they've caught up.
9. **Re-check upstream's `composer.json` `"php"` constraint and any new
   `symfony/polyfill-*` requires** against the target distros' shipped PHP
   versions. A polyfill dependency in `composer.json` is a signal that
   upstream calls a function from a newer PHP than some target distro
   ships; since this build never runs `composer install`
   (`fix-autoload-locations.patch` above), that polyfill is never actually
   installed, so such a call would fail at runtime with no build-time
   warning. `backport-php85-array-first-last.patch` is the existing
   example of this class of issue.

## Switching to Debian's official package

When Debian eventually packages Roundcube 1.7 and this PPA's package is
retired in favor of it, what to check:

1. **dbconfig-common schema migration collision (the likely failure, if
   not pre-empted)**. `dbc_go` (invoked from `roundcube-core.postinst`)
   gates purely on comparing the previously-installed package version
   against each shipped migration filename via `dpkg --compare-versions`
   - it has no idea what schema state the database is actually in. `apt`
   treats the switch as an ordinary upgrade of the same `roundcube-core`
   package name, so the "old version" dbconfig-common sees is literally
   this PPA's build version (`1.7.4-ppa<timestamp>`).

   Debian's own future packaging will almost certainly not freeze at
   exactly upstream `1.7.4` - by the time they package 1.7 at all, they'll
   likely start from whatever 1.7.x is current then. Since `sqlupdate`
   (below) naturally bundles everything since their last captured
   migration point into one file named after whatever version they're
   packaging, that file will almost certainly re-include the same
   `uploads` table and `session.expires_at` rename `1.7.4-1` already
   applies here. Whether dbconfig-common considers that file "new" and
   reruns it depends on how our version string compares to theirs at
   `dpkg --compare-versions` (not guaranteed either way - it depends on
   Debian's exact revision string, e.g. a `+dfsg` repack marker they've
   historically used), so don't rely on version ordering alone to avoid
   this. Neither statement is idempotent (`CREATE TABLE` without
   `IF NOT EXISTS`; `ALTER TABLE ... RENAME COLUMN` on an already-renamed
   column), so a rerun errors outright.

   **Recommended procedure - sidesteps version comparison entirely**
   rather than depending on it going the right way:

   a. Write `/etc/dbconfig-common/roundcube-core.conf` containing
      `dbc_upgrade='false'`. `dbc_read_package_config()` in
      `dbconfig-common`'s own `dpkg/common` script sets `dbc_upgrade=true`
      as a default and then sources this file if present, so its value
      wins deterministically - unlike preseeding the `dbconfig-upgrade`
      debconf question directly, which dbconfig-common's own source warns
      against relying on for exactly this ("we cannot fully trust
      debconf ... just edit the configuration files appropriately").
      This disables dbconfig-common's automatic schema migration for the
      *next* postinst run, regardless of what version string Debian's
      package carries.
   b. Install Debian's package (e.g. `apt install
      roundcube-core=<debian's-version>`, named explicitly since this is
      a deliberate action). Nothing gets auto-applied to the schema
      because of (a).
   c. Run upstream's own `bin/updatedb.sh` (packaged at
      `/usr/share/roundcube/bin/updatedb.sh` by both this PPA and Debian)
      against the live database. Unlike dbconfig-common, it reads the
      actual `system.roundcube-version` value out of the database and
      applies only genuinely-missing numbered migrations - correct
      regardless of how this PPA's and Debian's migration histories
      diverged, because it's driven by real schema state, not package
      version bookkeeping.
   d. Remove `/etc/dbconfig-common/roundcube-core.conf` (or set
      `dbc_upgrade='true'` back). This step isn't optional: the file
      persists across every future postinst run, not just this one, so
      leaving it in place would silently disable dbconfig-common's
      automatic migration for all of Debian's subsequent point-release
      upgrades too.

   If (a) is skipped and the collision happens live anyway: `apt upgrade`
   fails partway with a visible SQL error, `dpkg` marks `roundcube-core`
   half-configured, `apt` stops - a loud, recoverable maintainer-script
   failure, not silent data corruption. Read the error to see which
   migration file/statement failed, edit it on disk at
   `/usr/share/dbconfig-common/data/roundcube/upgrade/<db>/<version>` (a
   plain data file, not dpkg-protected) to drop the already-applied
   statements, then re-run `dpkg --configure roundcube-core`.

2. **apt priority/pinning**. If this PPA has been given elevated
   `Pin-Priority` over the default archive in `/etc/apt/preferences.d/`
   wherever it's deployed, that pin needs removing as part of the switch,
   or `apt` keeps preferring the PPA build even after Debian's is
   available. Since the switch is a deliberate action anyway (step 1
   above already needs one), installing Debian's package by explicit
   name and version rather than relying on ordinary upgrade-preference
   ordering sidesteps needing to reason about version comparison here
   too.

3. **Conffile prompts**. `/etc/roundcube/*` are dpkg conffiles; if their
   content differs between this PPA's build and Debian's, `dpkg` will
   interactively prompt (keep the local version or take the maintainer's)
   during the switch. Ordinary dpkg behavior, not a sign anything's wrong
   - just don't script the upgrade non-interactively without accounting
   for it.

4. **File layout**. Not expected to be an issue, but worth a sanity check
   if anything looks off: both packages install to the same final paths
   (dictated by `debian/rules` and upstream's own plugin code, not by how
   a file was fetched during the build), so `dpkg -L roundcube-core`
   should match closely between the two. `openpgp.min.js` in particular
   ends up at the same `usr/share/roundcube/plugins/enigma/` path either
   way, regardless of this package's live-fetch vs. Debian's probable
   secondary-tarball approach.

## Mechanisms that are easy to miss

### Why the pin isn't auto-tracked

`source.yml` uses `pin:`, not `track: latest_release` - deliberately.
Roundcube maintains two concurrent release lines, so `latest_release`
can't express "stay on the 1.7.x line." More importantly, every item in
the release checklist above needs a human to actually look at the diff
between old and new pinned commits before it's safe to ship - the CVE fix
alone required hand-rewriting for 1.7.4's refactored code, and the
composer floor patches are explicitly pinned-commit-scoped. Auto-bumping
would silently build against whatever's newest without any of that review
happening.

Empirically, patch-release schema changes are rare but not impossible to
rule out: both new upstream SQL migrations captured in `1.7.4-1` landed
exactly at the `1.7.0` tag and are unchanged through `1.7.4`, and no new
schema file appeared anywhere across the entire 1.6.x line (1.6.0 through
1.6.19, 19 point releases) - but the checklist's diff step still needs to
run every time regardless, since a missed migration fails silently rather
than at build time.

### Two separate test mechanisms

- **`dh_auto_test`** (upstream's phpunit suite, runs at build time) -
  enabled; runs the full suite (1335 tests) with `--fail-on-skipped`.
  None of salsa's own test-enablement patches apply as-is to 1.7.4 -
  upstream moved on since whichever version each was written against
  (phpunit-11 attribute syntax, the `tests/` tree's `Roundcube\Tests`
  namespace, and the `.github/` -> `.ci/` config-file move all postdate
  them) - so all of `adjust-test-environment-for-dep8`,
  `mark-flaky-tests-as-such`,
  `dont-force-set-session.gc_probability=1`, `fix-upstream-test-suite`,
  `Tests-Use-mocked-Guzzle-client-in-Modcss-action-test`,
  `Fix-FTBFS-with-phpunit-11`, `Fix-flaky-test` are dropped.
  `fix-autoload-locations.patch` is hand-rebased and kept (see "Ported
  forward but hand-rebased" above) - it's not test-only, it fixes a real
  runtime bug, but it does affect what `QrcodeTest::test_run` needs, see
  below. What's kept or added instead, driven by this package never
  running `composer install` (system PHP packages cover the runtime deps
  instead, via `dh_phpcomposer`/substvars only - no dependency-resolving
  step ever generates `vendor/autoload.php`):
  - `provide-tests-autoloader.patch` - two `spl_autoload_register`
    callbacks added to `tests/bootstrap.php`, replacing what
    `composer install` would otherwise have wired up: a PSR-4 mapping of
    the `Roundcube\Tests\` namespace onto `tests/`, and a classmap built
    by scanning every `plugins/*/composer.json`'s own
    `autoload.classmap`.
  - `fix-install-path.patch` - extended beyond Debian's original patch so
    `installer/index.php` also falls back to `RCUBE_INSTALL_PATH`,
    matching what it already did for `tests/bootstrap.php`:
    `tests/Public/InstallerTest.php` spawns a real PHP built-in server
    straight from the source tree and requests `installer.php`, which
    needs to find `program/include/iniset.php` there too, not at the
    hardcoded install path.
  - `mark-qrcode-test-flaky.patch` - tags `QrcodeTest::test_run` with the
    `qrcode` phpunit group, matching salsa's own dropped
    `mark-flaky-tests-as-such.patch` precedent for the same test.
    `debian/rules` excludes that group only on 32-bit archs, matching
    Debian's own `debian/control` precedent of only dropping
    `php-bacon-qr-code` there (BaconQrCode doesn't work on 32-bit, see
    https://github.com/Bacon/BaconQrCode/issues/76). On other archs the
    test now genuinely passes rather than being skipped, once
    `fix-autoload-locations.patch` (above) makes `BaconQrCode\*` classes
    resolvable at all.
  - `drop-slow-test-detector-extension.patch` - `tests/phpunit.xml`
    bootstraps `Ergebnis\PHPUnit\SlowTestDetector\Extension`, a
    require-dev-only composer dependency that (for the same no-`composer
    install` reason above) is never available; combined with
    `tests/phpunit.xml`'s own `failOnWarning="true"`, the resulting
    bootstrap warning was a hard build failure, so the extension's
    bootstrap entry is dropped.
  - `debian/rules`'s `execute_after_dh_install`/`execute_after_dh_link`
    also gained three unrelated fixes needed to get this far past
    `dh_auto_test` to a working build at all: the `.github/` -> `.ci/`
    config-test symlink target (upstream moved the file), installing
    `composer.json` instead of the now-removed `composer.json-dist`, and
    removing the `jqueryui` plugin's now-bundled `js/i18n/` datepicker
    files before symlinking that path to the system `libjs-jquery-ui`
    package's copy (upstream started bundling its own).
  - `Avoid-dependency-on-new-package-mlocati-ip-lib.patch`'s own
    CVE-regression test-suite hunk (extra `tests/Framework/UtilsTest.php`
    cases exercising the obfuscated-IP-literal parsing the CVE fix
    addresses) is restored, rebased onto the current
    PSR-4/attribute-based test structure. Restoring it surfaced a real
    gap: upstream's own `is_local_url()` `$nets` list only special-cases
    IPv4-*mapped* IPv6 addresses (`::ffff:a.b.c.d`, already covered by
    several of upstream's own existing test cases), not the older
    IPv4-*compatible* form (`::a.b.c.d`, deprecated by RFC4291 2.5.5.1
    but still resolved by `inet_pton(3)` and so by PHP/curl) that
    Debian's original, inlined version of this check also covered. A
    URL like `https://[::127.0.0.1]` was therefore not recognised as
    local - the same class of obfuscated-IP-literal SSRF-filter bypass
    this CVE fix otherwise closes. Fixed by adding a parallel
    `'::0.0.0.0/96'` entry to the `$nets` list.
- **`debian/tests/*`** (autopkgtest / DEP-8, runs after the package is
  built and installed) - not addressed at all yet. Exercises things like
  config file ownership/permissions, the dedicated system user, and the
  actual web installer. Debian ships 9 such tests (`apache2`,
  `check-upstream-version-number`, `cleanup`, `config-ownership-perms`,
  `control`, `dbconfig-no-thanks`, `hardening-dedicated-user`,
  `installer-checks`, `lighttpd`) - whether/how to port these is a separate
  open decision from `dh_auto_test`.

### dbconfig-common migrations and the build-time guard

Debian's dbconfig-common migrations (`debian/sql/<db>/<version>`) are a
separate mechanism from upstream's own schema tracking (timestamped files
in `SQL/{mysql,postgres,sqlite}/*.sql` plus upstream's own
`bin/updatedb.sh`). `roundcube-core.postinst`'s `dbc_go` runs any
`debian/sql/<db>/<version>` file whose version is newer than the previously
installed package version and no newer than the version being installed -
gated purely on `dpkg --compare-versions` of the filename, with no
awareness of what schema state the database is actually in.
`debian/rules`' `execute_after_dh_install` copies the whole `debian/sql/*`
tree into each package verbatim, so new files there need no other wiring.

Because that gate doesn't know about schema *content*, a missing migration
file fails silently - not at build time, only as a live schema mismatch
for anyone upgrading a pre-existing install. `recipe/build.sh`'s
`check_sql_migrations()` closes that gap: it compares the highest upstream
timestamp captured anywhere in `debian/sql/<db>/` (via its
`system.roundcube-version` marker, present in every migration file
regardless of which comment convention Debian used when writing it)
against every `SQL/{mysql,postgres,sqlite}/<timestamp>.sql` at the pinned
commit, and fails the build if anything upstream is newer than what's
captured. A failing build here means the packaging needs fixing before
merge - the alternative (a build that succeeds and installs, but silently
leaves upgraders on a stale schema) is worse.

`debian/sqlupdate` (vendored verbatim from salsa, unmodified, executable)
is Debian's own tool for regenerating `debian/sql/*/<version>` from
upstream's SQL files: it finds the last commit that touched `debian/sql/`,
diffs upstream's SQL directories against that point for newly-*added*
files, and concatenates them into one new migration file - refusing to
proceed if an already-captured file was *modified* rather than added
(that needs manual review, since it means upstream retroactively changed a
migration Debian already shipped). This is the same mechanism Debian's
real packagers use - salsa's `1.6~beta+dfsg-1` bundles two upstream
timestamps in one commit, the same way `1.7.4-1` bundles two here. It
relies on `debian/sql/`'s own linear git history to compute its diff base,
which this PPA repo doesn't have (only a point-in-time bulk copy), so
`1.7.4-1` was generated by hand using the same underlying logic rather
than by running this script. Once this package has its own linear git
history of `debian/sql/` changes across version bumps, prefer running it
directly: `debian/sqlupdate <new-deb-version> <old-upstream-tag-or-commit>`.
