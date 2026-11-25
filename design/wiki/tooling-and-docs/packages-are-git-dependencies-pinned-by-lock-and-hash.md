[Wiki](../index.md) › [Tooling and docs](index.md)

# Packages are git dependencies pinned by lock and hash

Decision (the prime-time lead for Chinmay, 2026-11-15): a project names git dependencies in `[dependencies]` as a table, `{ url, version | tag | sha }`; `ms install` is the only command that uses the network and pins commit plus content hash in `ms.lock`; fetched source is cached read-only outside the project; no registry, no build scripts, no C in packages. A package declares `effects = ["std.net.*"]` in its manifest (a TOML list, Chinmay 2026-11-15; a space-separated string is rejected, not accepted beside it) and the importer must allow them under `[effects]`. A package is a repository root (Chinmay, 2026-11-15: no `url//dir` form). The Postgres client is the first package, in `manuscript-lang/ms-pg`, not the standard library; version tags in either repository are Chinmay's to create, so pin a full commit.

Resolution (Chinmay, 2026-11-15: follow Rust): `version` is a Cargo-style requirement on tags (caret by default); one copy per repository per compatible range (major, or minor for 0.x), highest tag that satisfies every asker in the graph; another major is another copy with its own types. `ms.lock` has one line per copy keyed `github.com/acme/wire@v1.4.2`, a satisfying lock is kept, and `ms install --update @name` re-picks. `[project] version` is optional semver (CalVer fits); at a tagged commit it must equal the tag, the tag selects and the manifest only checks. Effects of a unified copy are checked against every dependent's allowance on every build. Design: [proposal](../../proposals/package-resolution.md), resolver.

Portability (bug bash 2026-11-18): the hash comes from the checked-out directory, so `ms install` rejects, from git's own file list and on every platform, a symbolic link, two paths equal after lowercasing, and a Windows-invalid name (`ms_package_reject_unportable` in `src/cli/package_validate.c`). Before, a Linux install pinned a case-colliding package that macOS and Windows could not reproduce. The test records such names with `git update-index --cacheinfo`, so it runs on every platform without creating them.

Why: copying source with an alias had no pin, origin or check.

Apply when: changing manifest parsing, import resolution, the loader's path confinement or logical file names, or `ms install`.

Verified: package files live outside the project root, so confinement and the logical name (`@name/path` instead of a path from the root) come from `Project::confinement_root` and `Project::logical`; code that does `rel(project.root, file)` on a package file gets a `..` path. A package's imports resolve through its own manifest, so its dependency names stay private. Hash input (an index of per-file hashes, checked per file as the loader reads) excludes `.git`, and `git` runs with `core.autocrlf=false`, or Windows hashes differ.

Editor: package files live in the cache, not under the project root, so a logical module name (`@pg/conn.ms`) maps to a path through `Analysis::package_roots`, and import completion reads `Project::deps` as well as `aliases`. A new place that turns a module name into a path must do the same.

Evidence: [proposal](../../proposals/packages.md), `src/cli/package_validate.c`, `src/compiler/project/solve*.c`.
Verify: `ctest --preset ci` (package tests) and the `install` command fixtures under `tests/commands/install`.
