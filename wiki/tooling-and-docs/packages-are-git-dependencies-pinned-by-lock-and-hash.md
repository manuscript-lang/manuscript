[Wiki](../index.md) › [Tooling and docs](index.md)

# Packages are git dependencies pinned by lock and hash

Decision (the prime-time lead for Chinmay, 2026-11-15): a project names git dependencies with a tag in `[dependencies]`; `ms fetch` is the only command that uses the network and pins commit plus content hash in `ms.lock`; fetched source is cached read-only outside the project; no registry, no build scripts, no C in packages. A package declares `effects` in its manifest and the importer must allow them under `[effects]`. A package is a repository root (Chinmay, 2026-11-15: no `url//dir` form). The Postgres client is the first package, in `manuscript-lang/ms-pg`, not the standard library; version tags in either repository are Chinmay's to create, so pin a full commit.

Why: copying source with an alias had no pin, origin or check.

Apply when: changing manifest parsing, import resolution, the loader's path confinement or logical file names, or `ms fetch`.

Verified: package files live outside the project root, so confinement and the logical name (`@name/path` instead of a path from the root) come from `Project::confinement_root` and `Project::logical`; code that does `rel(project.root, file)` on a package file gets a `..` path. A package's imports resolve through its own manifest, so its dependency names stay private. Hash input (an index of per-file hashes, checked per file as the loader reads) excludes `.git`, and `git` runs with `core.autocrlf=false`, or Windows hashes differ.

Editor: package files live in the cache, not under the project root, so a logical module name (`@pg/conn.ms`) maps to a path through `Analysis::package_roots`, and import completion reads `Project::deps` as well as `aliases`. A new place that turns a module name into a path must do the same.

Evidence: [proposal](../../proposals/packages.md), [packages.rs](../../crates/ms-driver/src/project/packages.rs), [fetch.rs](../../crates/ms-cli/src/fetch.rs), [test](../../crates/ms-cli/tests/packages.rs).
Verify: `cargo test -p ms-cli --test it packages`.
