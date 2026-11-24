# Packages: depend on another project's source by name and version

## Summary

- Problem: a project cannot use another project's source except by copying it, with nothing pinned or verified.
- Change: `[dependencies]` in `ms.toml` names git repositories at a tag; `ms install` pins them in `ms.lock` with a content hash; imports reach them as `@name/...`.
- Decision requested: approve the manifest, lock file, `ms install` command and import form below (user-visible).

## Status

Proposal, 2026-11-15, stage 1 built and checked against main at `7d4b8c2f`. Direction from Chinmay: packages before C interop; git URLs first, no registry; no third-party crates. Design calls settled by the prime-time lead for Chinmay: effects declared by the package and allowed by the importer, in-repo Postgres package, read-only cache, no build scripts, no registry.

## Problem

`documentation/developer-tooling/builds/project-configuration.md` says `ms` does not fetch third-party packages and copied code "is not pinned". Today the only way to share a library is:

```toml
[aliases]
"@pg" = "vendor/pg/src"
```

The copy can change silently, has no recorded origin, and a library's own dependencies must be copied by hand.

## Design

**Manifest.** A new `[dependencies]` table. Key is `@` plus one identifier, written like an alias. Value is a table: the git `url`, and one of `tag`, a full 40-character `sha`, or (see [package-resolution](package-resolution.md)) a semver `version` requirement.

```toml
[dependencies]
"@pg" = { url = "https://github.com/manuscript-lang/ms-pg.git", tag = "v0.1.0" }
```

- A branch name is rejected: it is not reproducible. A key cannot also be an alias, an `[embed]` name or `@std`.
- A package is an ordinary library project: it has an `ms.toml` with `source` and no `entry`.

**Imports.** `@name/path.ms` resolves under the package's `source` directory, exactly like a directory alias.

```manuscript
import connect from "@pg/client.ms"
```

- A package's own `[dependencies]` names are private to it. The consumer cannot import them, and two packages may use the same name for different packages.
- A package cannot import its consumer, and cannot declare `extern fn` (no C in packages).
- Different tags of one repository are different modules with different types; when they meet in one expression the error says two versions of the package are in the tree and names both paths and both tags. There is no version solver and no ranges; the consumer picks the tags.

**Lock file.** `ms.lock` beside `ms.toml`, committed. One line per package, in sorted order. A transitive package is keyed by its path from the project.

```text
"@pg" = "https://github.com/manuscript-lang/postgres.git 3f2a…(40 hex) sha256:9c1e…(64 hex)"
"@pg/@wire" = "https://github.com/manuscript-lang/wire.git 77b0…(40 hex) sha256:e4d2…(64 hex)"
```

- The hash is the SHA-256 of an index: one line per file in path order, holding the `/` path and the file's own SHA-256. `ms install` stores the index beside the package. A build checks the index against the lock once, then checks each file against its line as the loader reads it, so cost follows the files imported. Measured (release, 3 packages of 320 KB, none imported, 150 interleaved runs): whole-tree rehash added 12 ms to a 46 ms `ms check`; the index adds under 4 ms (median), minimums equal. Fetch passes `core.autocrlf=false` so Windows hashes match.
- Symbolic links and non-UTF-8 names in a package are errors, as in `[embed]`.

**Commands.**

- `ms install`: resolves each dependency, shallow-clones with the `git` program on `PATH` (no library, no new crate), verifies, stores it read-only at `<cache>/ms/packages/<sha256>/` (outside the project), and writes the lock. With a lock present it fetches exactly the locked revisions and fails on a hash mismatch (a moved tag). It prints each package, its revision, and the effects its files permit.
- `ms install --update @name` re-resolves one tag and rewrites its lock line.
- `check`, `build`, `run`, `test`, `lint` never use the network. A missing or stale lock, or a package missing from the cache, is an error that says to run `ms install`. A cached package is rehashed on first use in a build.
- A `file://` URL works, so tests and offline mirrors need no server.

**Effects.** A package declares what it may reach; the importer must allow it; the checker enforces both.

- Package `ms.toml`: `[project]` gains `effects = ["std.net.*", "std.fs.read"]`, a TOML list of the same patterns as `// ms: allow_effect`. No key means pure. The declaration is also the default permit for every function in the package, so its files need no `allow_effect` lines; a line can only narrow it.
- Consumer `ms.toml`: a new `[effects]` table gives, per dependency, what the project allows: `"@pg" = ["std.net.*"]`. A package whose declared effects are not covered is an error naming the missing effect. A package that adds an effect in a later tag fails the build until the consumer edits the manifest.
- Enforcement: the checker computes the effects each package function reaches, through its dependencies too, and `ms check` and `ms build` fail when one is outside the package's declaration. A package cannot hand a dependency effects it does not declare itself: the dependency's declaration must be inside the package's, and inside what the package's own `[effects]` allows.
- `ms install` prints each package's declared effects. No build scripts: a package is source only; nothing runs at fetch or build.

**Safety.**

- `ms.lock` is untrusted input: a revision must be 40 lowercase hex digits and a hash 64, a key must be `@name` segments, and a URL must pass the same check as the manifest (`https://` or `file://`, not starting with `-`, a plain tag).
- Every git call sets `GIT_TERMINAL_PROMPT=0` and `GIT_ALLOW_PROTOCOL` (`https`, plus `file` for the project's own dependencies), and puts `--` before positional arguments.
- A package's own dependencies must use `https://`: `file://` would read the machine that runs `ms install`.
- The checker rejects `extern fn` and `extern type` in any module of a package.

**Tooling.** `ms search_symbol` indexes fetched packages; modules show as `@pg/client.ms`, with the tag. `ms diagram` draws each package as one node labelled `@pg v0.1.0` in the module view. The language server resolves `@pg/...` through the lock: definitions open the cached file, and completion offers dependency names, package files and exports.

**Checked.** The manifest, `ms install`, the import and the offline check run against a `file://` repository in `crates/ms-cli/tests/packages.rs`. The checker rejects natives and undeclared effects in a package; the lock reader and the git calls are covered by unit tests and an end-to-end test with a tampered lock.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-driver/src/project/manifest.rs` | parse `[dependencies]`, lock reader and writer | unit: duplicate key, branch rejected, alias collision |
| `crates/ms-driver/src/imports.rs`, `load.rs` | resolve `@name/` per package; private names | conformance: two versions, private name |
| `crates/ms-cli` | `ms install`, hashing (reuse `ms-tooling` `sha256.rs`), cache | e2e on a `file://` repo, all platforms |
| `crates/ms-check` | package scope: reject `extern`, cap reachable effects at the declaration | `crates/ms-cli/tests/packages.rs` |
| `manuscript-lang/ms-pg` | first package: Postgres client over `@std/net` TCP and TLS, in its own repository so it is a repository-root package | e2e against a database, nightly |
| `crates/ms-tooling`, `ms-lsp` | search_symbol, diagram, lint across packages | existing suites plus one case each |
| `documentation/` | replace "copied dependencies" with packages | doc example tests |

## Alternatives

- Do nothing: copy plus alias. No pin, no hash, no origin; it is the problem.
- Go-style URL in the import: ties every source file to a host and breaks "import by name".
- Version ranges with a solver: needs an algorithm and is not reproducible; distinct versions side by side give the same reach with no solver.
- Registry: later. A git URL and tag map onto a registry entry without changing imports.
- Vendoring only (`ms install` into the project): the cache plus hash already gives the same bytes; a copy can be added later.

## Stages

1. Manifest, lock, `ms install`, resolution, `extern` rule; green on a `file://` fixture on Linux, macOS, Windows.
2. search_symbol, diagram, lint, LSP.
3. Docs, wiki, and a sample service depending on a package; dispatch macOS and Windows CI.

## Open questions

- None. Decided: the Postgres client is the first package, in `manuscript-lang/ms-pg`, not in the standard library. A package is a repository root; there is no subdirectory form (`url//dir`).
