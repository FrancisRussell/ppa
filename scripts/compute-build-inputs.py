#!/usr/bin/env python3
"""
Computes build inputs for a package build.

Usage: compute-build-inputs.py <package> <arch> <codename> <container>

Outputs JSON with two fields:
  - key: deterministic inputs that identify the build (hashed to produce
    inputs_key_hash): arch, codename, commit, container, package, recipe_files
  - meta: supplementary source info not part of the key: ref, repo

Requires GITHUB_TOKEN in the environment for latest_release packages.
"""

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def resolve_source(package: str) -> dict:
    result = subprocess.run(
        [str(REPO_ROOT / "scripts" / "resolve_source.py"), package],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def compute_recipe_files(recipe_dir: Path) -> dict:
    file_paths = []
    for root, dirs, filenames in os.walk(recipe_dir, followlinks=True):
        dirs.sort()
        for filename in sorted(filenames):
            file_paths.append(Path(root) / filename)
    file_paths.sort()

    result = {}
    for filepath in file_paths:
        relpath = str(filepath.relative_to(recipe_dir))
        h = hashlib.blake2b(digest_size=32)
        with open(filepath, "rb") as f:
            h.update(f.read())
        result[relpath] = h.hexdigest()
    return result


def main():
    if len(sys.argv) != 5:
        print(
            f"Usage: {sys.argv[0]} <package> <arch> <codename> <container>",
            file=sys.stderr,
        )
        sys.exit(1)

    package, arch, codename, container = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

    source = resolve_source(package)
    recipe_dir = REPO_ROOT / "packages" / package / "recipe"

    build_key = {
        "arch": arch,
        "codename": codename,
        "commit": source["commit"],
        "container": container,
        "package": package,
        "recipe_files": compute_recipe_files(recipe_dir),
    }

    metadata = {
        "ref": source["ref"],
        "repo": source["repo"],
    }

    print(json.dumps({"key": build_key, "meta": metadata}))


if __name__ == "__main__":
    main()
