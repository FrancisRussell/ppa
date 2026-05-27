#!/usr/bin/env python3
"""
Generates the build matrix for a package.

Usage: generate_matrix.py [<package>] [--force]

Outputs a pretty-printed JSON array of matrix entries. Each entry contains
codename, arch, container, inputs_key, inputs_meta, and inputs_key_hash.
Skips targets whose inputs_key_hash already exists in gh-pages unless
--force is given.

Requires GITHUB_TOKEN in the environment for latest_release packages.
"""

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

import rfc8785
import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent


def resolve_source(package: str) -> dict:
    result = subprocess.run(
        [str(REPO_ROOT / "scripts" / "resolve_source.py"), package],
        stdout=subprocess.PIPE,
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


def inputs_key_hash(build_key: dict) -> str:
    return hashlib.blake2b(rfc8785.dumps(build_key), digest_size=32).hexdigest()


def hash_exists_in_ghpages(hash_str: str, codename: str, package: str, arch: str) -> bool:
    path = f"builds/{codename}/{package}/{arch}/{hash_str}.json"
    result = subprocess.run(["git", "show", f"FETCH_HEAD:{path}"], capture_output=True)
    return result.returncode == 0


def all_packages() -> list[str]:
    packages_dir = REPO_ROOT / "packages"
    return sorted(d.name for d in packages_dir.iterdir() if d.is_dir() and (d / "source.yml").exists())


def build_matrix_for_package(package: str, force: bool, default_targets: list) -> list:
    source_yml = REPO_ROOT / "packages" / package / "source.yml"
    with open(source_yml) as f:
        source_config = yaml.safe_load(f)

    targets = source_config.get("targets", default_targets)
    source = resolve_source(package)
    recipe_files = compute_recipe_files(REPO_ROOT / "packages" / package / "recipe")

    entries = []
    for target in targets:
        codename = target["codename"]
        arch = target["arch"]
        container = target["container"]

        build_key = {
            "arch": arch,
            "codename": codename,
            "commit": source["commit"],
            "container": container,
            "package": package,
            "recipe_files": recipe_files,
        }
        metadata = {"ref": source["ref"], "repo": source["repo"]}
        ref = metadata["ref"]
        hash_str = inputs_key_hash(build_key)

        if not force and hash_exists_in_ghpages(hash_str, codename, package, arch):
            continue

        entries.append(
            {
                "name": f"{package}:{ref[:8] if len(ref) == 40 else ref} ({container}, {arch})",
                "package": package,
                "pool_subdir": f"{package[0]}/{package}",
                "codename": codename,
                "arch": arch,
                "container": container,
                "inputs_key_hash": hash_str,
                "inputs_key": build_key,
                "inputs_meta": metadata,
            }
        )

    return entries


def main():
    force = "--force" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) > 1:
        print(f"Usage: {sys.argv[0]} [<package>] [--force]", file=sys.stderr)
        sys.exit(1)

    packages = args if args else all_packages()

    targets_file = REPO_ROOT / "build-targets.yaml"
    with open(targets_file) as f:
        default_targets = yaml.safe_load(f)

    subprocess.run(["git", "fetch", "origin", "gh-pages"], capture_output=True)

    matrix = []
    for package in packages:
        matrix.extend(build_matrix_for_package(package, force, default_targets))

    print(json.dumps(matrix, indent=2))


if __name__ == "__main__":
    main()
