#!/usr/bin/env python3
"""
Generates the build matrix for a package.

Usage: generate_matrix.py <package> [--force]

Outputs JSON array of matrix entries. Each entry contains codename, arch,
container, repo, build_hash, and build_inputs_json. Skips targets whose
build hash already exists in gh-pages unless --force is given.

Requires GITHUB_TOKEN in the environment for latest_release packages.
"""

import hashlib
import json
import subprocess
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent


def compute_build_inputs(package: str, arch: str, codename: str, container: str) -> str:
    script = REPO_ROOT / 'scripts' / 'compute-build-inputs.py'
    result = subprocess.run(
        [str(script), package, arch, codename, container],
        capture_output=True, text=True, check=True
    )
    return result.stdout.strip()


def build_hash(inputs_json: str) -> str:
    return hashlib.blake2b(inputs_json.encode(), digest_size=32).hexdigest()


def hash_exists_in_ghpages(hash_str: str, codename: str, package: str, arch: str) -> bool:
    path = f'builds/{codename}/{package}/{arch}/{hash_str}.json'
    result = subprocess.run(
        ['git', 'show', f'FETCH_HEAD:{path}'],
        capture_output=True
    )
    return result.returncode == 0


def main():
    force = '--force' in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) != 1:
        print(f'Usage: {sys.argv[0]} <package> [--force]', file=sys.stderr)
        sys.exit(1)

    package = args[0]

    targets_file = REPO_ROOT / 'build-targets.yaml'
    with open(targets_file) as f:
        targets = yaml.safe_load(f)

    source_yml = REPO_ROOT / 'packages' / package / 'source.yml'
    with open(source_yml) as f:
        source_config = yaml.safe_load(f)

    if 'targets' in source_config:
        targets = source_config['targets']

    subprocess.run(
        ['git', 'fetch', 'origin', 'gh-pages'],
        capture_output=True
    )

    sys.path.insert(0, str(REPO_ROOT / 'scripts'))
    from resolve_source import resolve
    source = resolve(package)

    matrix = []
    for target in targets:
        codename = target['codename']
        arch = target['arch']
        container = target['container']

        inputs_json = compute_build_inputs(package, arch, codename, container)
        hash_str = build_hash(inputs_json)

        if not force and hash_exists_in_ghpages(hash_str, codename, package, arch):
            continue

        matrix.append({
            'name': f'{package}:{source["ref"][:8] if len(source["ref"]) == 40 else source["ref"]} ({container}, {arch})',
            'codename': codename,
            'arch': arch,
            'container': container,
            'ref': source['ref'],
            'build_hash': hash_str,
            'build_inputs_json': inputs_json,
        })

    print(json.dumps(matrix))


if __name__ == '__main__':
    main()
