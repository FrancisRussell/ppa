#!/usr/bin/env python3
"""
Resolves a package's source.yml to a specific git commit hash.

Usage: resolve-source.py <package>
Outputs JSON: {repo, ref, commit}
Requires GITHUB_TOKEN in the environment for latest_release packages.
"""

import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent


def _github_get(path: str) -> dict:
    token = os.environ.get('GITHUB_TOKEN', '')
    url = f'https://api.github.com{path}'
    req = urllib.request.Request(url, headers={'Authorization': f'Bearer {token}'})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def _resolve_latest_release(repo_url: str) -> tuple[str, str]:
    repo_path = repo_url.removeprefix('https://github.com/')
    data = _github_get(f'/repos/{repo_path}/releases/latest')
    tag = data.get('tag_name')
    if not tag:
        raise ValueError(f'Failed to fetch latest release for {repo_path}')
    result = subprocess.run(
        ['git', 'ls-remote', repo_url, f'refs/tags/{tag}'],
        capture_output=True, text=True, check=True
    )
    commit = result.stdout.split()[0] if result.stdout.strip() else None
    if not commit:
        raise ValueError(f'Failed to resolve tag {tag} to a commit for {repo_url}')
    return tag, commit


def resolve(package: str) -> dict:
    source_yml = REPO_ROOT / 'packages' / package / 'source.yml'
    with open(source_yml) as f:
        source = yaml.safe_load(f)

    repo = source['repo']

    if 'pin' in source:
        commit = source['pin']
        return {'repo': repo, 'ref': commit, 'commit': commit}
    elif source.get('track') == 'latest_release':
        if not repo.startswith('https://github.com/'):
            raise ValueError(f'track: latest_release is only supported for GitHub repos, got: {repo}')
        tag, commit = _resolve_latest_release(repo)
        return {'repo': repo, 'ref': tag, 'commit': commit}
    else:
        raise ValueError(f'source.yml must specify either pin or track')


def main():
    if len(sys.argv) != 2:
        print(f'Usage: {sys.argv[0]} <package>', file=sys.stderr)
        sys.exit(1)
    result = resolve(sys.argv[1])
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()
