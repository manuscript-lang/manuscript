# Git packages (design proposal)

## Summary

- Problem: a Manuscript project cannot depend on another Manuscript project. The documented workaround is to copy the sources in and record the upstream revision by hand (#121). Nothing checks or pins that copy.
- Change: a `[dependencies]` table in `ms.toml` whose values name a git repository and an exact tag or commit, a generated `ms.lock`, a shared read-only cache, and imports through the existing `@name/...` alias form. A build uses one revision per repository, chosen by Go-style minimal version selection over semver tags.
- No new syntax, keyword, or type. `check`, `build`, `run`, and `test` resolve and fetch when the lock is missing or stale; the only new CLI surface is a `--locked` flag. Fetching shells out to the system `git`.
- Cost: an estimated 900 to 1,300 lines of Rust, mostly in `ms-driver` and `ms-cli`, plus small changes in `ms-lsp` and `ms-lower`. Tests use local `file://` repositories on Linux, macOS, and Windows.
- Decision requested: approve the manifest spelling, the one-revision rule, and auto-locking on build before implementation starts.

## Status

- Proposal, 2026-10-27, written against `main` at `a33486b`.
- Direction (Chinmay, 2026-10-27): "spike on how can we enable libraries/packages in manuscript, first version needs to be git only then we can think about a dedicated package registry".
- Not implemented. A skeptical review was done on 2026-10-27; its findings are applied, see [Review](#review).
- The `.ms` examples pass `ms check` and `ms run` with the library copied in under an `[aliases]` entry. The import form is the existing directory alias.

## Problem

- Verified: `ms.toml` accepts only `[project]` and `[aliases]`. `[dependencies]` is rejected with "there are no dependency tables, so copy the sources into the project and map them with [aliases]" (`crates/ms-driver/src/project/manifest.rs:155`).
- Verified: every resolved path must stay inside the project root (`source_path`, `crates/ms-driver/src/project/paths.rs:101`, "path escapes project root"). An alias to a sibling project or a symlink out of the root is rejected.
- Verified: [project configuration](../documentation/developer-tooling/builds/project-configuration.md#library-projects-and-copied-dependencies) tells users to copy library sources and record URL, revision, and checksums by hand. The compiler verifies none of it.
- Reported: in #121, a graph library consumed by a routes app could only be shared as a copy inside the app.
- Non-goals for v1:
  - A registry, a version-range syntax (`^1.2`), or a SAT/PubGrub solver.
  - Native code in packages. There is no Rust, no `bindings.json`, and no build scripts, and `extern def` is rejected in dependency modules.
  - Branch dependencies, git submodules, Git LFS, and packages in a repository subdirectory.
  - Running or checking a dependency's tests, lints, or formatter.
  - A minimum `ms` version per package.

## Design

### The rule

A dependency is a git repository with an `ms.toml` at its root. The consuming project names it in `[dependencies]` and imports its modules as `@name/<path>.ms`, where `<path>` is relative to the dependency's `project.source`. Every build uses exactly one revision of each repository, and `ms.lock` records it.

### A library

A library is an ordinary project without `entry`, which is already supported (see "Omitted library entries" in `.experts/compiler.md`):

```toml
# github.com/acme/graph/ms.toml
[project]
name = "graph"
source = "src"
```

```manuscript
# src/paths.ms
export type Edge:
    source: Int
    target: Int
    weight: Int

export def total_weight(edges: List[Edge]) -> Int:
    var total = 0
    for edge in edges:
        total += edge.weight
    return total
```

- The exports are the existing `export` declarations. Every module under `source` can be imported. v1 has no separate export list and no `internal` directory.
- When a library is used as a dependency, its `entry`, its test files, and the `test` blocks inside its modules are ignored.
- A library's own `[aliases]` and `[dependencies]` apply only to its own modules. Its alias targets must stay inside its own root.
- To publish a version: `git tag v1.2.0 && git push --tags`.

### Depending on it

```toml
[project]
name = "routes"
source = "src"
entry = "src/main.ms"

[dependencies]
graph = "https://github.com/acme/graph#v1.2.0"
json5 = "git@github.com:acme/json5.git#3f9c2e7d0a4b6c18e5f1d2a3b4c5d6e7f8091a2b"
```

```manuscript
from "@graph/paths.ms" import Edge, total_weight

export def main() -> Int:
    let edges = [Edge(source: 1, target: 2, weight: 5), Edge(source: 2, target: 3, weight: 7)]
    return total_weight(edges) - 12
```

- The value is `<git url>#<ref>`. `#` never appears in git URLs or scp-style user info, so a missing ref is reported instead of misparsed. `manifest_line` already keeps `#` inside quoted strings (`manifest.rs:357`).
- The ref is a tag (`v1.2.0`, `release-3`) or a full 40- or 64-hex commit id. Branch names and abbreviated commits are rejected with "dependency refs must be a tag or a full commit id; branches move, so tag a release or copy the commit id".
- The key is the import name: `graph` makes `@graph/...` available. It follows the alias identifier rule, and `@` + key must not equal an `[aliases]` key or `@std`.
- Values stay double-quoted strings, so the manifest reader keeps its single value form and needs no inline-table parser.
- A dependency is visible only to the package that declares it. `routes` cannot import modules from a package that only `graph` depends on.

### Import resolution

Today `@name/...` is a directory alias. A dependency is a directory alias whose target is the `source` directory of the cached checkout.

- Resolution is per package. `resolve_import` uses the aliases and dependencies of the manifest that owns the importing file, not those of the root project.
- Confinement is per package. A file inside a dependency can only resolve paths inside that dependency's root, and the existing "path escapes project root" check runs against the dependency root.
- Module identity stays the canonical file path. The cache path includes the commit, so two packages that depend on the same repository share one module and one set of nominal types.
- `@std` is unchanged and still cannot be shadowed.
- The logical name of a dependency file comes from the package identity, not the local key: `github.com/acme/graph@v1.2.0/src/paths.ms`. A file has one name no matter which package imports it first. The name is used in diagnostics, in debug info, and as the module key, so the binary contains no home-directory paths.
- One `ms-driver` helper maps a logical name to its on-disk path. Every site that joins `source_root` and a logical file today calls it instead (listed under [Components touched](#components-touched)). Terminal and `--json` output give a dependency file's absolute cache path, using the absolute-path branch those sites already have.

### Version selection

A package's identity is its repository location in normalized form. The normalization lowercases everything and removes the scheme (`https`, `http`, `ssh`, `git`), user info, port, a leading `www.`, a trailing `/`, and `.git`. So `https://github.com/Acme/Graph`, `ssh://git@github.com/acme/graph.git`, and `git@github.com:acme/graph` are one package.

Selection works like Go's MVS:

1. Start with the root project's requirements and visit every manifest they reach, once for each revision that is required anywhere.
2. For each package, collect the refs that all visited manifests require.
3. If the root project declares the package, the root's ref wins (the override). If the override is a semver tag lower than another requirer's tag with the same major version, the build fails and names that requirer: "routes pins graph v1.1.0, but layout requires v1.2.0; raise the pin to at least v1.2.0".
4. Otherwise, if every requirement names the same ref, that ref is selected.
5. Otherwise, if every requirement is a release semver tag (`vMAJOR.MINOR.PATCH`, with no pre-release suffix) and they share one `MAJOR`, the highest is selected.
6. Otherwise the build fails and names each requirer: "graph is required at v1.2.0 by routes and at v2.0.1 by layout; add graph to [dependencies] in ms.toml with the revision to use".

- Requirements from every visited revision count, as in Go. So the result does not depend on the order of visits.
- A package that depends on itself, directly or through others, is rejected.
- Two different identities whose manifests have the same `[project] name` are rejected. This catches normalization misses and forks used side by side, both of which would split types.
- The fetch URL is the root project's spelling if the root declares the package. Otherwise it is the spelling of the first requirer in sorted identity order. `ms.lock` records it.
- Why one revision per repository: types are nominal per module. Two revisions of `graph` would produce two `Edge` types, and passing one where the other is expected fails with "expected Edge, found Edge", which is a known Cargo failure. Allowing one revision avoids that without a solver.

### `ms.lock`

`ms.lock` is generated next to `ms.toml`, committed, and never edited by hand. It reuses the manifest syntax:

```toml
# Generated by ms. Commit this file; do not edit it.
[packages]
"github.com/acme/graph" = "https://github.com/acme/graph v1.2.0 9f1c2e7d0a4b6c18e5f1d2a3b4c5d6e7f8091a2b"
"github.com/acme/json5" = "git@github.com:acme/json5.git 3f9c2e7d0a4b6c18e5f1d2a3b4c5d6e7f8091a2b 3f9c2e7d0a4b6c18e5f1d2a3b4c5d6e7f8091a2b"
```

- There is one line for each package in the selected graph: the identity, then the fetch URL, the selected ref, and the commit id. The file is rewritten to exactly the selected set, so packages that are no longer used drop out.
- The commit id pins the content. v1 has no separate content hash. A file hash would differ across platforms because of `core.autocrlf`, `core.symlinks`, and `.gitattributes` filters. A registry that serves archives would add one later.
- A lock line is current when its ref equals the ref that selection picks from the manifests. Lines that are stale or missing are resolved again. Lines that are current never touch the network.
- A moved tag is an error, not a silent update: "tag v1.2.0 of github.com/acme/graph now points to 1b2c...; ms.lock recorded 9f1c...; delete its line from ms.lock to accept the new commit". It is detected whenever the tag is fetched again.
- `ms.lock` is written to a temporary file and then renamed into place, under the package-cache lock described below.

### Fetching and the cache

- `check`, `build`, `run`, `test`, `lint`, and `profile` on a project with `[dependencies]` first bring the lock up to date and fill the cache, then load the module graph. They print one line per fetched package to standard error, for example `fetched graph v1.2.0 (9f1c2e7)`.
- With a current lock and a full cache, no network access happens and no `git` process starts.
- `--locked` on those commands fails if `ms.lock` would change and never resolves refs over the network. It still fetches commits that the lock already names. CI and parallel runs use it.
- `ms-lsp` never fetches. It loads the locked revisions that are already in the cache. A package that is missing, or a lock that is stale, produces a diagnostic on that `[dependencies]` line: "graph is not fetched at v1.2.0; run ms check ms.toml".
- `git` is the system executable, run non-interactively (`GIT_TERMINAL_PROMPT=0`), so SSH keys, credential helpers, and proxies work the same way they do for `git clone`. If `git` is missing, the diagnostic names the dependency and asks the user to install git.
- Database: one bare repository per package, at `<cache>/ms/git/db/<id>/`, where `<id>` is the first 12 hex characters of SHA-256(identity). The short id keeps paths under Windows `MAX_PATH`.
  - A tag is fetched as `git fetch --depth 1 <url> refs/tags/<tag>:refs/tags/<tag>`, and the commit it peels to is recorded. Resolving and fetching happen in one step, so the tag cannot move in between.
  - A commit is fetched with `git fetch --depth 1 <url> <commit>`. If the server refuses an unadvertised object, which happens with protocol v0, a full `git fetch <url>` follows.
- Checkout: `git -c core.autocrlf=false -c core.symlinks=false --git-dir <db> --work-tree <tmp> checkout -f <commit> -- .` runs with no attribute filters, and then the directory is renamed to `<cache>/ms/git/src/<id>/<commit>/`.
  - If the target already exists, that counts as success. Another process finished the same checkout, and a finished checkout is never modified.
  - A tree with two paths that differ only in case is rejected at checkout, because it cannot be checked out the same way on macOS and Windows.
- Concurrency: each package has a file lock, `<cache>/ms/git/db/<id>.lock`, held during fetch and checkout. Two `ms` processes on one machine wait for each other instead of racing on git's `shallow.lock`.
- `<cache>` is the directory that the pinned `lld` already uses: `%LOCALAPPDATA%` on Windows, otherwise `$XDG_CACHE_HOME`, `$HOME/.cache`, or the temporary directory. `ms-clif/src/link/lld.rs` and `ms-cli/src/engine/runtime.rs` each have their own cache-root helper today. They merge into one, and no third copy is added.
- No dependency code runs during fetch or build. The bare repository has no hooks, submodules are not fetched, attribute filters (including LFS) are disabled, and packages have no build scripts or `extern def`.

### Data flow

```text
before:  ms.toml ──► Project{aliases} ──► Loader(resolve_import, one root) ──► check ──► lower ──► link

after:   ms.toml ─┐
                  ├─► resolve (lock, git, cache) ──► Packages{identity, root, source, aliases, deps}*
         ms.lock ─┘                                      │
                                                         ▼
                              Loader(resolve_import with the importer's package) ──► check ──► lower ──► link
```

### Leaving room for a registry

- A registry would add a value form without a URL, for example `graph = "1.2.0"`, plus a default registry setting. Git values keep working.
- The lock already records an identity, a version, and a source. A registry adds an archive content hash, which is what Go's module proxy and crates.io verify downloads against.
- The identity, not the local name, is the package's global name. A registry can map names to identities without changing any imports.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-driver/src/project/manifest.rs` | parse `[dependencies]` and replace the copy-the-sources advice | manifest accept and reject tests with exact diagnostics |
| `crates/ms-driver/src/project/` (new `packages.rs`, `lock.rs`) | lock read and write, identity normalization, version selection, the package table read from the cache | unit tests for selection steps 3 to 6, a stale lock, a moved tag, pruning |
| `crates/ms-driver/src/project/paths.rs` | `resolve_import` and `source_path` take the importer's package; add the logical-name-to-path helper | escaping a dependency is rejected; a transitive dependency cannot be imported |
| `crates/ms-driver/src/load.rs` | the `Loader` maps each canonical path to its package and gives dependency files identity-based logical names | a diamond dependency shares one module and one type |
| `crates/ms-check` | reject `extern def` in dependency modules | reject fixture |
| `crates/ms-lower/src/func.rs:270` | collect `test` blocks only from root-package modules, not dependencies | `ms test` does not run a dependency's inline tests |
| `crates/ms-cli/src/engine/` | resolve and fetch with `git` before loading; `--locked`; progress lines; one cache-root helper (`runtime.rs:55`) | e2e tests with local `file://` repositories on Linux, macOS, and Windows, including protocol v0 and two concurrent runs |
| path joins of `source_root` and a logical file | use the helper: `engine/mod.rs:162`, `engine/tooling.rs:233` (and lint `--fix` never writes into the cache), `engine/tooling.rs:324` (watch), `engine/build.rs:53`, `engine/run.rs:92`, `profile.rs:669` (`--json`), `ms-lsp/src/editor.rs:381`, `ms-lsp/src/analysis.rs:113` | a diagnostic inside a dependency prints a real path in text and `--json` |
| `crates/ms-lsp/src/query.rs:38`, `completion.rs:758` | `ms search_symbol` and import completion include dependency modules and `@name` keys | search finds `total_weight` from the consumer |
| `ms-mir`, `ms-clif`, `ms-rt`, syntax, formatter, `stdlib/` | unchanged | existing suites |
| docs | rewrite "Library projects and copied dependencies", add a dependencies page, mention `@name` dependencies in modules/declarations | `make docs`, book link check |

## Survey

| | Go modules | Cargo git deps | SwiftPM | Deno |
| --- | --- | --- | --- | --- |
| Declares | `go.mod` `require path vX` | `{ git, tag \| rev \| branch }` | `Package.swift` (executable) `.package(url:, from:)` | `deno.json` `imports` map |
| Import spelling | full module path in source | crate name | product name | mapped name or URL |
| Lock | `go.sum` content hashes | `Cargo.lock` with commit | `Package.resolved` | `deno.lock` integrity hashes |
| Selection | MVS, one version per major | semver solver, many versions | PubGrub over semver ranges | per URL |
| Fetch | shells out to `git`; proxy and checksum DB | libgit2, gitoxide, or the `git` CLI | shells out to `git` | HTTP |
| Code at build | none | `build.rs` | plugins | none |

What changed the decision:

- Go: MVS and a read-only shared cache keep resolution deterministic without a solver, and shelling out to `git` gets authentication for free. Rejected: URLs in import strings, because a fork or a move then means editing every importing file.
- Cargo: adopted auto-updating the lock on build, `--locked`, and using the local key as the import name. Rejected: several versions of one package, which splits nominal types, and build scripts.
- SwiftPM: git tags as versions are enough for a long time. Rejected: an executable manifest and a range solver.
- Deno: started with URLs in imports, then moved to a name map plus a registry (JSR). Manuscript's `[aliases]` is already that kind of map.

## Alternatives

- Do nothing and keep copying sources. This works today and is documented, but nothing checks the recorded revision or checksums, and every project that shares code with another hits it (#121).
- Smallest version: exact refs plus the root override, with no MVS (steps 4 and 6 only). It saves about 40 lines, but then every diamond on two patch versions needs a root override. MVS is kept because it is small, and Go shows it is enough.
- Path dependencies (`graph = "../graph"`) help while developing a library next to an app (#121), but the user asked for git first. They are deferred to the [open questions](#open-questions).
- A Rust git library (`gix` or `git2`) would remove the need for `git` on the machine, but it brings a large dependency tree and its own auth and proxy handling. Rejected: `git` is present wherever source is cloned, and Go and SwiftPM make the same choice.
- Inline-table values (`{ git = "...", tag = "..." }`) are familiar from Cargo but would need a TOML inline-table parser for one feature. Rejected for v1.
- A separate `ms fetch` or `ms add` command would avoid builds touching the network, at the cost of an extra step for every agent and person. Rejected: auto-locking with a fast path for a current lock, plus `--locked`, covers the same need.
- URL in the import string (Go, early Deno) needs no manifest table but ties every import to a location. Rejected for the reason Deno moved away from it.
- A content hash in the lock (removed after review): it varies by platform, and the commit id already pins the content.
- Drawbacks of the chosen design:
  - A build can need the network the first time.
  - An unreachable remote fails a cold build.
  - Projects with dependencies need `git` installed. Projects without dependencies are unaffected.

## Staging and verification

1. Multi-package loading without git: a package table built from directories, per-package `resolve_import` and confinement, identity logical names, the path helper and its call sites, test-block and `extern def` filtering. Check: `cargo nextest run -p ms-driver -p ms-cli` with fixture packages in temp directories, and a diamond that shares one type.
2. `[dependencies]` in the manifest, reading and writing `ms.lock`, version selection. Check: unit tests for each step and diagnostic.
3. `git` fetch and cache, file locks, `--locked`. Check: e2e tests that create `file://` repositories with `git init` and tags, on Linux, macOS, and Windows CI, including `protocol.version=0` and two concurrent `ms check` runs.
4. LSP, `search_symbol`, completion, and docs. Check: `make verify`, `make docs`.

- Gate: in stage 1, `ms-check` and `ms-lower` change only by the per-module "dependency" flag (for `extern def` and test blocks). If checking or lowering needs more than that, stop and revisit.
- Every stage passes `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo nextest run --workspace`, and `make verify`.

## Open questions

- Path dependencies for local development (`graph = "../graph"`, with no lock line). Recommendation: add them after stage 4, since they reuse stage 1 directly.
- Package-private modules, like Go's `internal/`. Recommendation: not in v1. Every module under `source` is public, which matches how files work today.
- Monorepos, meaning a package in a repository subdirectory. Recommendation: defer until someone needs it.

## Review

Independent skeptical review, 2026-10-27. The proposal survives, because do-nothing leaves copies unverified. These changes were applied:

- The ref separator changed from `@` to `#`. With `@`, a missing ref in `git@host:org/repo` was misparsed as the ref.
- The SHA-256 content hash was dropped. It varied across platforms with `autocrlf`, symlinks, and filters, and the commit id already pins the content.
- Fetching a commit with `--depth 1` fails on protocol v0 servers (reproduced with git 2.43 over `file://`). Tags are now fetched by ref name, with a full-fetch fallback for commits.
- Added a per-package file lock, rename-exists-is-success for checkouts, and an atomic `ms.lock` write for concurrent processes.
- `ms-lower` collects inline `test` blocks from every non-`@std` module. Dependency modules are now excluded, and the stage-1 gate allows that flag.
- Logical names now come from the identity, not the per-package key. Every `source_root` + logical-file join site is listed and uses one helper. The `--json` paths stay valid.
- Selection now counts requirements from every visited revision, as Go does. Pre-release tags are excluded. A root override below a requirer's version fails and names that requirer.
- Normalization now covers case, `http` versus `https`, ports, and `www.`. Two identities with the same `[project] name` are rejected.
- Case-colliding trees are rejected at checkout, and cache ids were shortened for Windows `MAX_PATH`.
- `extern def` is rejected in dependency modules, which enforces the no-native-code non-goal.
- `--locked` was added. Lock pruning and LSP behavior with a stale lock are now specified. `search_symbol` and completion now cover dependencies.
- The build-cache row was removed (there is no executable cache) and so was the formatter row (it never reaches the cache). The #121 description was corrected.
