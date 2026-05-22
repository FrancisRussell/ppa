# PPA Build System Design

## Background

This repository builds and publishes Debian packages for software not available
in standard distro repositories. Each package has its own build script and
Debian packaging metadata. A GitHub Actions workflow builds each package on a
schedule or when packaging files change, and publishes the resulting `.deb` to
a gh-pages-hosted APT repository.

---

## Design Decisions

### One generic workflow, not per-package workflows

Per-package workflows duplicate matrix generation, build environment setup,
publishing, and deployment. A single generic workflow reads per-package config
and drives the whole process. Adding a new package means adding config files,
not copying a workflow.

### Recipe directory

Each package has a `recipe/` directory whose entire contents are hashed to
produce the build cache key. The convention is: if it affects build output, it
lives in `recipe/`. Config that only affects CI behaviour (caching settings)
lives outside `recipe/` and is not hashed. This avoids maintaining an explicit
list of files to hash — the directory structure enforces what's in scope.

### Hash-based rebuild detection

Rebuilds are gated on a content hash of all build inputs rather than a version
string. This means packaging changes (fixed postinst, updated rules, etc.)
naturally trigger a rebuild without needing a force flag, because the hash
changes. A build record keyed by hash is stored in gh-pages; a build is skipped
if and only if its record already exists.

The previous version-string approach required a force flag to handle packaging
changes, and the logic for detecting packaging changes via `github.event.commits`
doesn't work — the GitHub push event commits array does not include file change
lists.

### Canonical JSON for hash input

`compute-build-inputs.py` takes the package name, arch, and container image as
arguments. It reads `source.yml` to resolve the source ref, computes the recipe
hash, and outputs canonical JSON (sorted keys, compact) combining all inputs. The build hash is
the BLAKE2 digest of this JSON. This makes the hash input self-documenting: the
build record stored in gh-pages contains the same pre-build fields, extended
with post-build data (deb filenames, version, timestamp). The hash can always be
recomputed from the record.

### Recipe hash computation

`compute-build-inputs.py` walks the recipe directory, following symlinks so
that symlinked scripts (e.g. `get-version.sh`) hash their target content rather
than just the link path. File paths are sorted for stability across filesystems.
BLAKE2 is used throughout for speed.

### build-deps.yml canonicalization

`build-deps.yml` declares apt packages and an optional Rust toolchain. It is
part of the recipe and therefore hashed. To ensure semantically equivalent
files always produce the same hash, lists are sorted and keys are normalised
before hashing.

### get-version.sh per package

Version derivation is package-specific. A `get-version.sh` script in each
`recipe/` outputs the version string to stdout. Packages with standard GitHub
release tagging symlink to a shared `scripts/get-version-release.sh`. Custom
versioning logic (e.g. pinned commit + hardcoded base version) lives in the
package's own script. The workflow always calls `recipe/get-version.sh` without
needing to know which case applies.

`get-version.sh` lives inside `recipe/` and is therefore hashed — changing
version derivation logic triggers a rebuild.

### caching.yml outside recipe

sccache and cargo registry caching are CI performance optimisations that do not
affect build output. They live in `caching.yml` alongside (not inside)
`recipe/` and are not hashed. If a `rust` section is present in
`build-deps.yml`, sccache and cargo caching are enabled automatically.

sccache is a separate concept from Rust — it can also wrap C/C++ compilers —
so it is represented as a boolean flag rather than being implied solely by the
presence of a Rust toolchain.

### Rust toolchain cache keying

Specifying `toolchain: stable` in `build-deps.yml` would produce a stale cache
key when the toolchain updates. After installation, the actual toolchain version
is resolved via `rustc --version` and used in the cache key instead.

### Per-package target overrides over global defaults

`build-targets.yaml` defines the default set of (codename, arch, container)
triples. `source.yml` can override or extend this per package. Most packages
inherit defaults; exceptions are explicit. This avoids repeating the full target
list in every package when adding a new distro.

### ppa version suffix

Built packages use a UTC timestamp suffix `~ppa<YYYYmmddHHMM>` rather than a
hardcoded counter. This ensures every rebuild produces a version apt will offer
as an upgrade without manually incrementing a counter.

When publishing, old debs for the same package + upstream version + arch are
pruned from the pool. The pool therefore never accumulates multiple ppa builds
of the same upstream version.

### Pool pruning via build records

Build records stored in gh-pages include the list of deb filenames produced.
Pruning reads these records to identify files to delete — precise, no glob
matching, and correct across arch boundaries.

### Python for complex logic

Shell is used for simple per-package scripts (`get-version.sh`, `build.sh`).
Python is used where YAML/JSON manipulation, file walking, or hash computation
would produce unreadable shell: canonical JSON + hash generation, matrix
computation, and pool pruning.

---

## File Layout

```
build-targets.yaml              # default (codename, arch, container) targets

packages/<pkg>/
  source.yml                    # repo URL, version strategy, target overrides
  caching.yml                   # sccache/cargo flags (not hashed)
  recipe/                       # everything here is hashed
    build.sh                    # compile + package
    build-deps.yml              # apt packages, optional rust section
    get-version.sh              # outputs version string (may be a symlink)
    files/                      # auxiliary files consumed by build.sh
      debian/                   # debian packaging metadata
      <other files>

scripts/
  compute-build-inputs.py       # produces canonical JSON and build hash
  get-version-release.sh        # shared get-version for latest-release packages

.github/
  workflows/
    build.yml                   # single generic workflow
  actions/
    publish-ppa/
```

---

## Config File Schemas

### source.yml
```yaml
repo: https://github.com/lldap/lldap
track: latest_release           # or: pin: <commit-hash>
version_template: "{tag}"       # for pinned commits: e.g. "0.2.2~beta+git{date}"

targets:                        # optional overrides over build-targets.yaml
  - codename: trixie
    arch: amd64
    container: debian:trixie
```

### build-deps.yml
```yaml
apt:
  - build-essential
  - pkg-config

rust:                           # optional; presence enables sccache + cargo cache
  toolchain: stable
  targets:
    - wasm32-unknown-unknown
  cargo_tools:
    - wasm-pack
```

### caching.yml
```yaml
sccache: true
cargo_registry: true
```

---

## Build Hash and gh-pages Records

Running `compute-build-inputs.py <package> <arch> <container>` produces
canonical JSON (sorted keys, compact) and prints the BLAKE2 hash of that JSON
to stdout. The script reads `packages/<pkg>/source.yml` and resolves the source
ref internally (GitHub API call for `track: latest_release`, pinned commit hash
for `pin:`). Example JSON:
```json
{
  "arch": "amd64",
  "container": "debian:trixie",
  "package": "lldap",
  "recipe_hash": "<blake2 digest of recipe dir contents>",
  "source_ref": "v0.6.3"
}
```

Record stored at `builds/<codename>/<package>/<arch>/<hash>.json`:
```json
{
  "arch": "amd64",
  "built_at": "2026-05-22T14:06:39Z",
  "container": "debian:trixie",
  "debs": ["lldap_0.6.3~ppa202605221347_amd64.deb"],
  "package": "lldap",
  "recipe_hash": "<hash>",
  "source_ref": "v0.6.3",
  "version": "0.6.3~ppa202605221347"
}
```
