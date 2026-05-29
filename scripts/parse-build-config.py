#!/usr/bin/env python3
"""
Read a package's caching.yml and recipe/build-deps.yml and emit the contents
as GitHub Actions step outputs (and GITHUB_ENV vars for sccache). Called from
the build workflow before the install steps so each step can be conditional on
the relevant output. Prints key=value to stdout when run outside GitHub Actions.
"""

import sys
import os
import yaml


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <package>", file=sys.stderr)
        sys.exit(1)

    pkg = sys.argv[1]

    try:
        with open(f"packages/{pkg}/caching.yml") as f:
            caching = yaml.safe_load(f) or {}
    except FileNotFoundError:
        caching = {}

    try:
        with open(f"packages/{pkg}/recipe/build-deps.yml") as f:
            deps = yaml.safe_load(f) or {}
    except FileNotFoundError:
        deps = {}

    rust = deps.get("rust", {})
    go = deps.get("go", {})
    node = deps.get("node", {})
    sccache_raw = caching.get("sccache", False)
    if isinstance(sccache_raw, dict):
        use_sccache = True
        sccache_persist = sccache_raw.get("persist", True)
    else:
        use_sccache = bool(sccache_raw)
        sccache_persist = use_sccache
    use_cargo = caching.get("cargo", False)
    outputs = {
        "use_sccache": str(use_sccache).lower(),
        "sccache_persist": str(sccache_persist).lower(),
        "use_cargo": str(use_cargo).lower(),
        "apt_deps": " ".join(deps.get("apt", [])),
        "has_rust": "true" if rust else "false",
        "rust_toolchain": rust.get("toolchain", "stable"),
        "rust_targets": " ".join(rust.get("targets", [])),
        "rust_components": " ".join(rust.get("components", [])),
        "cargo_tools": " ".join(rust.get("cargo_tools", [])),
        "has_go": "true" if go else "false",
        "go_version_file": go.get("version_file", ""),
        "go_sum_file": os.path.join(os.path.dirname(go.get("version_file", "")), "go.sum") if go else "",
        "has_node": "true" if node else "false",
        "node_version": str(node.get("version", "")),
    }

    output_file = os.environ.get("GITHUB_OUTPUT")
    if output_file:
        with open(output_file, "a") as f:
            for k, v in outputs.items():
                f.write(f"{k}={v}\n")
    else:
        for k, v in outputs.items():
            print(f"{k}={v}")

    env_file = os.environ.get("GITHUB_ENV")
    if env_file and use_sccache:
        with open(env_file, "a") as f:
            f.write("RUSTC_WRAPPER=sccache\n")
            f.write("CMAKE_C_COMPILER_LAUNCHER=sccache\n")
            f.write("CMAKE_CXX_COMPILER_LAUNCHER=sccache\n")


if __name__ == "__main__":
    main()
