#!/usr/bin/env python3
"""
Resolves a package's source.yml to a specific git commit hash.

Usage: resolve_source.py <package>
Outputs JSON: {repo, ref, commit}
Requires GITHUB_TOKEN in the environment for latest_release packages.
"""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent

_RETRY_DELAYS = [5, 15]


def _is_retryable(exc: Exception) -> bool:
    if isinstance(exc, urllib.error.HTTPError):
        return exc.code >= 500
    if isinstance(exc, urllib.error.URLError):
        return True
    if isinstance(exc, subprocess.CalledProcessError):
        return exc.returncode == 128
    return False


def _with_retries(fn):
    delays = _RETRY_DELAYS + [None]
    for attempt, delay in enumerate(delays):
        try:
            return fn()
        except Exception as e:
            if delay is None or not _is_retryable(e):
                raise
            print(f"Attempt {attempt + 1} failed ({e}), retrying in {delay}s...", file=sys.stderr)
            time.sleep(delay)


def _github_get(path: str) -> dict:
    token = os.environ.get("GITHUB_TOKEN", "")
    url = f"https://api.github.com{path}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def _resolve_tag_to_commit(repo_url: str, tag: str) -> str:
    def run():
        result = subprocess.run(
            ["git", "ls-remote", repo_url, f"refs/tags/{tag}"],
            stdout=subprocess.PIPE,
            text=True,
            check=True,
        )
        commit = result.stdout.split()[0] if result.stdout.strip() else None
        if not commit:
            raise ValueError(f"Failed to resolve tag {tag} to a commit for {repo_url}")
        return commit

    return _with_retries(run)


def _resolve_latest_release_github(repo_url: str) -> tuple[str, str]:
    repo_path = repo_url.removeprefix("https://github.com/")

    def fetch():
        data = _github_get(f"/repos/{repo_path}/releases/latest")
        tag = data.get("tag_name")
        if not tag:
            raise ValueError(f"Failed to fetch latest release for {repo_path}")
        return tag

    tag = _with_retries(fetch)
    return tag, _resolve_tag_to_commit(repo_url, tag)


def _resolve_latest_release_codeberg(repo_url: str) -> tuple[str, str]:
    repo_path = repo_url.removeprefix("https://codeberg.org/")
    url = f"https://codeberg.org/api/v1/repos/{repo_path}/releases/latest"

    def fetch():
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
        tag = data.get("tag_name")
        if not tag:
            raise ValueError(f"Failed to fetch latest release for {repo_path}")
        return tag

    tag = _with_retries(fetch)
    return tag, _resolve_tag_to_commit(repo_url, tag)


def resolve(package: str) -> dict:
    source_yml = REPO_ROOT / "packages" / package / "source.yml"
    with open(source_yml) as f:
        source = yaml.safe_load(f)

    repo = source["repo"]

    if "pin" in source:
        commit = source["pin"]
        return {"repo": repo, "ref": commit, "commit": commit}
    elif source.get("track") == "latest_release":
        if repo.startswith("https://github.com/"):
            tag, commit = _resolve_latest_release_github(repo)
        elif repo.startswith("https://codeberg.org/"):
            tag, commit = _resolve_latest_release_codeberg(repo)
        else:
            raise ValueError(f"track: latest_release only supports GitHub and Codeberg repos, got: {repo}")
        return {"repo": repo, "ref": tag, "commit": commit}
    else:
        raise ValueError("source.yml must specify either pin or track")


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <package>", file=sys.stderr)
        sys.exit(1)
    result = resolve(sys.argv[1])
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
