#!/usr/bin/env python3
"""
Computes canonical build inputs JSON for a package build.

Usage: compute-build-inputs.py <package> <arch> <codename> <container>

Outputs canonical JSON (sorted keys, compact) combining:
  - package name, arch, codename, container image
  - resolved source commit hash (via resolve_source)
  - recipe directory content hash (BLAKE2b, follows symlinks)

The BLAKE2b hash of this JSON is the build identifier.
Requires GITHUB_TOKEN in the environment for latest_release packages.
"""

import hashlib
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / 'scripts'))
from resolve_source import resolve as resolve_source


def compute_recipe_hash(recipe_dir: Path) -> str:
    file_paths = []
    for root, dirs, filenames in os.walk(recipe_dir, followlinks=True):
        dirs.sort()
        for filename in filenames:
            file_paths.append(Path(root) / filename)
    file_paths.sort()

    outer = hashlib.blake2b(digest_size=32)
    for filepath in file_paths:
        relpath = str(filepath.relative_to(recipe_dir))
        file_hasher = hashlib.blake2b(digest_size=32)
        with open(filepath, 'rb') as f:
            file_hasher.update(f.read())
        outer.update(relpath.encode())
        outer.update(b'\0')
        outer.update(file_hasher.digest())
    return outer.hexdigest()


def main():
    if len(sys.argv) != 5:
        print(f'Usage: {sys.argv[0]} <package> <arch> <codename> <container>', file=sys.stderr)
        sys.exit(1)

    package, arch, codename, container = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

    source = resolve_source(package)
    recipe_dir = REPO_ROOT / 'packages' / package / 'recipe'
    recipe_hash = compute_recipe_hash(recipe_dir)

    inputs = {
        'arch': arch,
        'codename': codename,
        'commit': source['commit'],
        'container': container,
        'package': package,
        'recipe_hash': recipe_hash,
        'repo': source['repo'],
    }

    print(json.dumps(inputs, sort_keys=True, separators=(',', ':')))


if __name__ == '__main__':
    main()
