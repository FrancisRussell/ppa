# PPA Build System Design

## Background

This repository builds and publishes Debian packages for software not available
in standard distro repositories. Each package has its own build script and
Debian packaging metadata. A GitHub Actions workflow builds each package on a
schedule or when packaging files change, and publishes the resulting `.deb` to
a gh-pages-hosted APT repository.

---

## Design Decisions

### One generic workflow

A single `build.yml` workflow reads per-package config and drives the entire
build, publish, and deploy process. Adding a new package requires only a
`source.yml` and recipe — no workflow changes.

### Recipe directory

Each package has a `recipe/` directory whose entire contents are hashed into
the build key. The convention is: if it affects build output, it lives in
`recipe/`. Config that only affects CI behaviour (caching settings) lives
outside `recipe/` and is excluded from the hash. This avoids maintaining an
explicit list of files to hash — the directory structure enforces what is in
scope.

### Hash-based rebuild detection

Builds are gated on a content hash of all build inputs rather than a version
string. Packaging changes (a fixed postinst, updated build rules, etc.)
naturally trigger a rebuild without a force flag, because the hash changes. A
build record keyed by hash is stored in gh-pages; a target is skipped if and
only if its record already exists. A `--force` flag bypasses this check.

This approach also handles the case where a source package is re-released at
the same version tag — as long as the commit hash differs, the build key
differs.

### Build key and metadata separation

`compute-build-inputs.py` returns two dicts:

- `key`: deterministic inputs that fully identify the build — arch, codename,
  container image, source commit, package name, and per-file hashes of the
  recipe directory. This is hashed to produce the `inputs_key_hash`.
- `meta`: supplementary source information not part of the key — the human-
  readable ref (tag or branch) and the repo URL.

Keeping these separate prevents `meta` fields from affecting whether a rebuild
is triggered, while still making them available in build records for
traceability.

### Canonical JSON hashing

The `inputs_key` dict is serialised using RFC 8785 (JSON Canonicalisation
Scheme) via the `rfc8785` library before hashing. RFC 8785 defines a
deterministic encoding independent of key insertion order, float representation,
and other implementation details that would make ad-hoc JSON serialisation
fragile. The hash is a 32-byte BLAKE2b digest of the canonical form.

### Per-file recipe hashing

The recipe directory is hashed by walking it and computing an individual
BLAKE2b hash for each file. These per-file hashes are stored in the build key
as a `recipe_files` dict, making it possible to inspect which file changed
between two builds by comparing their keys. Symlinks are followed so that
shared scripts hash their target content rather than the link path.

### get-version.sh per package

Version derivation is package-specific. A `get-version.sh` script in each
`recipe/` outputs the upstream version string to stdout. Packages with standard
GitHub release tagging symlink to a shared `scripts/get-version-tag.sh`.
Custom versioning logic lives in the package's own script. The workflow always
calls `recipe/get-version.sh` without needing to know which case applies.

`get-version.sh` may also hardcode parts of the version that are not derivable
from the source or git tags — for example, a pre-release label (`-beta`) that
upstream embeds in source files but does not reflect in tag names, or a
`+git<date>` suffix for projects that do not use release tags at all.

`get-version.sh` lives inside `recipe/` and is therefore hashed — changing
version derivation logic triggers a rebuild.

### caching.yml outside recipe

sccache and cargo registry caching are CI performance optimisations that do not
affect build output. They live in `caching.yml` alongside (not inside)
`recipe/` and are not hashed.

sccache can wrap both Rust and C/C++ compilers, so it is a separate flag from
the Rust toolchain declaration rather than being implied by it. Both
`caching.yml` and `build-deps.yml` are optional; a package with neither needs
no caching or Rust configuration.

### Per-package target overrides over global defaults

`build-targets.yaml` defines the default set of (codename, arch, container)
triples. `source.yml` can override this per package. Most packages inherit the
defaults; exceptions are explicit. This avoids repeating the full target list
in every package config.

### ppa version suffix

Built packages use a UTC timestamp suffix `-ppa<YYYYmmddHHMM>` as the Debian
revision rather than a hardcoded counter. This ensures every rebuild produces a
version APT will offer as an upgrade without manually incrementing a counter.

When publishing, old debs for the same package + upstream version + arch are
pruned from the pool. The pool therefore never accumulates multiple ppa builds
of the same upstream version.

### Pool pruning via build records

Build records stored in gh-pages include the list of deb filenames produced by
each build. Pruning reads these records to identify which files to delete —
precise and correct across arch boundaries, with no glob matching.

### Single-commit gh-pages history for LFS hygiene

`.deb` files are stored in gh-pages via Git LFS. LFS objects are reference-
counted against commits: an object is only reclaimable once no commit in the
branch history points to it. A normal append-only history would permanently
retain LFS objects for every pruned or superseded `.deb`, even after those
files are removed from the pool, because the earlier commits that added them
would still exist.

To avoid this, every publish amends the single existing gh-pages commit rather
than appending a new one. The branch therefore always has exactly one commit,
so any LFS object removed from the pool is immediately unreferenced and
eligible for pruning. Force-pushing is required as a consequence; this is safe
because gh-pages is a generated branch that is never edited by hand.

### Concurrent publish safety

Multiple matrix jobs may finish and attempt to publish to gh-pages
simultaneously. Each job clones gh-pages, stages its packages and regenerated
APT metadata, and pushes using `--force-with-lease`. If the push is rejected
(another job pushed first), the job fetches the new state, resets to it,
re-stages its own packages on top (so the combined result contains both jobs'
packages and fully regenerated metadata), and retries. Up to three attempts are
made.

### Python for complex logic

Shell is used for simple per-package scripts (`get-version.sh`, `build.sh`).
Python is used where YAML/JSON manipulation, file walking, or hash computation
would produce unreadable shell: build key computation, matrix generation, and
source resolution.

---

## Build Flow

Each workflow run passes through three jobs.

**`check`** (runs once): `generate_matrix.py` calls `resolve_source.py` for
each package to resolve `source.yml` to a pinned commit, then
`compute-build-inputs.py` for each (package, codename, arch) triple to produce
a `{key, meta}` pair. Each key is hashed; if a matching build record already
exists on gh-pages the target is skipped. The surviving targets form the CI
matrix. The current gh-pages SHA is also captured here so the `deploy` job can
detect whether any build job actually published.

**`build`** (one job per matrix entry):

1. `parse-build-config.py <package>` reads `caching.yml` and `build-deps.yml`
   and emits GitHub Actions step outputs that control the subsequent install
   steps (apt deps, Rust toolchain, sccache, etc.).
2. The source repo is cloned and the pinned commit checked out.
3. `recipe/get-version.sh <src>` is called to obtain the upstream version string.
4. `recipe/build.sh <version> <src> <pool> <codename>` runs the package-specific
   build. For most packages this copies `recipe/files/debian/` into the source
   tree and delegates to `scripts/build-deb.sh`, which:
   - Sources `maintainer.sh` for maintainer identity (`DEBEMAIL`, `DEBFULLNAME`).
   - If `debian/source/format` is present, creates an `.orig.tar.gz` from the
     git checkout and does a source+binary build; otherwise binary-only.
   - Runs `mk-build-deps` to satisfy `Build-Depends`.
   - Runs `dch` to prepend a timestamped changelog entry.
   - Runs `dpkg-buildpackage` and moves all produced artifacts (`.deb`, `.dsc`,
     `.tar.*`) to the pool directory.
5. The `publish-ppa` action clones gh-pages and stages the publish: it reads
   existing build records to find any artifacts from prior builds of the same
   upstream version, removes them from the pool, then copies the new artifacts
   in. `update-repo.sh` regenerates the APT `Packages`, `Sources`, and
   `Release` indices, and a new build record is written. The staged result is
   then committed and pushed. If a concurrent job has pushed in the meantime the
   push is rejected; the action fetches, resets to the new remote state,
   re-stages on top of it (so both jobs' packages end up in the final commit),
   and retries up to three times.

**`deploy`** (runs once, after all build jobs): If gh-pages changed since the
SHA captured in `check`, the `deploy-site` action deploys the updated gh-pages
branch to GitHub Pages.

---

## File Layout

```
build-targets.yaml              # default (codename, arch, container) targets

packages/<pkg>/
  source.yml                    # repo URL, version strategy, target overrides
  caching.yml                   # sccache/cargo flags (not hashed)
  recipe/                       # everything here is hashed into the build key
    build.sh                    # compile + package
    build-deps.yml              # apt packages, optional rust section
    get-version.sh              # outputs version string (may be a symlink)
    files/                      # auxiliary files consumed by build.sh
      debian/                   # debian packaging metadata

scripts/
  build-deb.sh                  # shared script: stamp changelog, run dpkg-buildpackage, collect artifacts
  maintainer.sh                 # exports DEBEMAIL/DEBFULLNAME for dch
  compute-build-inputs.py       # outputs {key, meta} for a build target
  generate_matrix.py            # computes hashes and builds the CI matrix
  get-version-tag.sh            # shared get-version for latest-release packages
  parse-build-config.py         # emits GitHub Actions outputs from caching.yml / build-deps.yml
  resolve_source.py             # resolves source.yml to a commit + ref
  update-repo.sh                # regenerates APT Packages, Sources, and Release indices

.github/
  workflows/
    build.yml                   # single generic workflow
  actions/
    publish-ppa/                # stages debs, regenerates APT metadata, pushes
    deploy-site/                # deploys gh-pages to GitHub Pages
```

---

## Config File Schemas

### source.yml
```yaml
repo: https://github.com/lldap/lldap
track: latest_release           # or: pin: <commit-hash>

targets:                        # optional override of build-targets.yaml
  - codename: trixie
    arch: amd64
    container: debian:trixie
```

### build-deps.yml
All keys are optional; the file itself may be omitted entirely.
```yaml
apt:                            # optional list of apt packages
  - build-essential
  - pkg-config

rust:                           # optional; enables rustup install
  toolchain: stable
  targets:
    - wasm32-unknown-unknown
  cargo_tools:
    - wasm-pack
```

### caching.yml
```yaml
sccache: true                   # wrap compilers with sccache
cargo: true                     # cache cargo registry index and crates
```

---

## Build Key and gh-pages Records

`compute-build-inputs.py <package> <arch> <codename> <container>` outputs:

```json
{
  "key": {
    "arch": "<arch>",
    "codename": "<codename>",
    "commit": "<full git commit hash>",
    "container": "<container image>",
    "package": "<package>",
    "recipe_files": {
      "build-deps.yml": "<blake2b>",
      "build.sh": "<blake2b>",
      "files/debian/changelog": "<blake2b>"
    }
  },
  "meta": {
    "ref": "<tag or branch>",
    "repo": "<upstream repo URL>"
  }
}
```

`generate_matrix.py` hashes `key` via RFC 8785 + BLAKE2b to produce
`inputs_key_hash`. A build record is stored at
`builds/<codename>/<package>/<arch>/<inputs_key_hash>.json`:

```json
{
  "inputs": {
    "key": { "...": "..." },
    "meta": { "ref": "<tag or branch>", "repo": "<upstream repo URL>" }
  },
  "output": {
    "files": ["<package>_<package_version>_<arch>.deb"],
    "meta": {
      "built_at": "<ISO 8601 timestamp>",
      "package_version": "<upstream_version>-ppa<YYYYmmddHHMM>",
      "run_url": "<Actions run URL>",
      "upstream_version": "<upstream_version>"
    }
  }
}
```
