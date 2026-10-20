#!/usr/bin/env python3
"""Print the workspace crates a change can affect, or `all` when it reaches beyond crates.

Reads changed paths, one per line, from standard input. A change confined to
crates/<name>/ affects <name> and every crate that depends on it, directly or through
dev- and build-dependencies. Anything else (manifests, lockfile, toolchain, scripts,
stdlib sources, workflows, fixtures) can change every crate's behavior, so it prints `all`.
Markdown files do not run code and are ignored. With `--complement` it prints the crates
that are not affected instead (for `cargo --workspace --exclude`), or nothing for `all`.
"""
import pathlib
import sys
import tomllib

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Edges Cargo does not declare: ms-cli's build script builds and embeds ms-native.
IMPLICIT = {"ms-cli": {"ms-native"}}


def dependency_names(manifest):
    tables = [manifest.get(k, {}) for k in ("dependencies", "dev-dependencies", "build-dependencies")]
    for target in manifest.get("target", {}).values():
        tables += [target.get(k, {}) for k in ("dependencies", "dev-dependencies", "build-dependencies")]
    return {name for table in tables for name in table}


def main():
    complement = "--complement" in sys.argv[1:]
    packages = {}
    for path in sorted((ROOT / "crates").glob("*/Cargo.toml")):
        manifest = tomllib.loads(path.read_text())
        name = manifest["package"]["name"]
        packages[path.parent.name] = (name, dependency_names(manifest) | IMPLICIT.get(name, set()))
    names = {directory: name for directory, (name, _) in packages.items()}
    changed = set()
    for line in sys.stdin.read().split():
        if line.endswith(".md"):
            continue
        parts = line.split("/")
        if len(parts) < 3 or parts[0] != "crates" or parts[1] not in packages:
            print("" if complement else "all")
            return
        changed.add(names[parts[1]])
    affected = set(changed)
    grew = True
    while grew:
        grew = False
        for name, deps in packages.values():
            if name not in affected and deps & affected:
                affected.add(name)
                grew = True
    if complement:
        affected = {name for name, _ in packages.values()} - affected
    print(" ".join(sorted(affected)))


main()
