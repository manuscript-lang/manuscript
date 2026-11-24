+++
title = "Project configuration"
weight = 1
+++

# Project configuration

Use a project when your program grows beyond one file, needs tests beside its source, or bundles assets. The `ms.toml` at its root tells `ms` where to find those inputs. Each `.ms` file is one module.

## A project manifest

Create a project, then check its generated source and test:

```sh
ms init store
cd store
ms check ms.toml
```

The check prints:

```text
Checked ms.toml (2 modules)
```

`init` creates `ms.toml`, `src/main.ms` and `test.ms`. It also creates a `.gitignore` that excludes the local build cache and a `.gitattributes` that keeps source and manifests on LF line endings in Windows checkouts. Run the following examples from `store`.

As the project grows, add aliases to the generated manifest:

```toml
[project]
name = "store"
source = "./src"
entry = "./src/main.ms"

[aliases]
"@domain" = "./src/domain"
"@customers" = "./src/domain/customers.ms"
```

- `name` names the project; `source` is its source directory.
- `entry` is the executable entry file. Omit it for a library; an empty or invalid entry is an error. There is no default.
- All manifest paths resolve relative to the directory containing `ms.toml`. The entry is not relative to `source`.
- The manifest has only these tables: `[project]`, `[workspace]`, `[aliases]`, `[embed]`, `[dependencies]` and `[effects]`. Unknown or duplicate tables and keys are rejected.
- `ms.toml` is TOML. Strings are quoted, effects are lists of strings (`["std.net.*"]`), and a dependency is a table (`{ url = "...", tag = "v1" }`, or `{ path = "..." }` for a [workspace](#workspaces) member). Quote keys that start with `@`.
- Application modules are found by following imports from the entry, not listed in the manifest.
- The compiler supplies the prelude and version-matched `@std` modules. To reuse other Manuscript source, use [packages](#packages).

## Embedded files

`[embed]` bakes a directory into the program. Each key is an import name written like an alias, and each value is a directory below the project root:

```toml
[embed]
"@assets" = "./assets"
```

Create `assets/message.txt` containing `hello from assets` followed by a newline. Add `import files from "@assets"` above the generated `main`, then replace its body with this fragment:

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
    tree := files()
    text := tree.read("message.txt", null).get().decode_utf8().get()
    print(text.trim())
    return 0
```

```sh
ms run ms.toml
```

```text
hello from assets
```

This example uses `get()` because the file and its UTF-8 contents are known at build time. For variable paths or data, handle missing files and decode failures explicitly.

- `import files from "@assets"` imports a module that `ms` generates from the directory when the project loads. Write the name alone: `"@assets/x.ms"` is an error.
- `files()` returns an `EmbeddedTree` from `@std/os/tree.ms`, so `read`, `children` and `walk` work as they do on a `host_tree`. Creating the tree costs one map entry per file; `read` copies only the file it returns.
- Paths in the tree are relative to the directory and use `/` on every platform. Entries are listed in byte order. Hidden files are included.
- Symbolic links, names that are not valid UTF-8, and names that differ only by letter case are errors. A file may be at most 16 MiB and a directory 64 MiB in total.
- The program stores the files as raw bytes in read-only data, alongside the program code and lookup metadata. Editing, adding or removing a file rebuilds the program.
- An embed name cannot also be an alias.

## Commands and module discovery

| Command | Behavior |
| --- | --- |
| `ms check <ms.toml>` | Check all source modules and discovered tests; validate entry when present |
| `ms build <ms.toml>` | Check, lower to MIR, generate native object code, and link the executable; requires entry |
| `ms lint <ms.toml>` | Check and lint reachable modules; libraries include all source modules and discovered tests |
| `ms test <ms.toml>` | Execute tests from entry and discovered test files; libraries include all source modules too |

`ms check ms.toml` checks every `.ms` file below `project.source`, including modules the entry does not import, plus `test.ms` and `*_test.ms` anywhere below the project root. It never runs `main` or tests and needs no native toolchain. Text output reports the number of modules checked.

Discovered source filenames and visited directory names must be valid UTF-8. An invalid name is a resolution error that says to rename it; discovery never substitutes another path.

- Discovery skips hidden directories (such as `.ms-cache`), `vendor`, `node_modules`, and directory symlinks. Entries and imports are always followed.
- Files outside the source directory are checked only if imported, the entry, or tests.
- `ms check file.ms` checks that file and its imports only.
- `check` and `lint` also take several targets; see [analysis input selection](../implementation.md#selecting-independent-analysis-inputs).

## Library projects {#library-projects-and-copied-dependencies}

A library needs no placeholder `main`. `ms init --lib greeter` creates one with `src/lib.ms` and a test. A library manifest looks like this:

```toml
[project]
name = "graph"
source = "src"
```

`check`, `lint`, and `test` include every source module and discovered test. `run`, `build`, `emit`, and `profile` need an executable entry: add `entry = "src/main.ms"` and declare `fn main()`.

Share library code as a [package](#packages).

## Packages

A package is a library project in a git repository. Name it under `[dependencies]` with a table holding the repository `url` and exactly one of `version`, `tag` or `sha`. Write the name like an alias.

```toml
[dependencies]
"@pg" = { url = "https://github.com/manuscript-lang/ms-pg.git", version = "1.2" }

[effects]
"@pg" = ["std.net.*", "std.clock.read", "std.random.read"]
```

- `version` is a semver requirement on the repository's tags, as in Cargo: `1.2` and `^1.2` mean at least 1.2.0 and below 2.0.0; `~1.2.3` means 1.2.3 up to 1.3.0; `=1.2.3` means that version. For `0.x` the minor is the boundary (`^0.4.1` stays below 0.5.0) and `^0.0.3` is that one version. `0` and `0.0` alone are rejected because they span incompatible releases, and `>=`, `<` and comma ranges are not supported. A tag names a version with or without a leading `v`. A pre-release is chosen only when the requirement names one.
- `tag` is exactly that tag and `sha` is exactly that 40-digit commit. A repository is either pinned or required by version across the whole dependency graph, not both.

`ms add <url> --version 1.2` (or `--tag <tag>`, or `--sha <commit>`) writes the dependency into `ms.toml` and installs it. `ms remove @name` takes it out again.

`ms install` resolves everything `ms.toml` names and downloads each package with `git`. It records the commit and a content hash in `ms.lock` and prints what each package may reach. Commit `ms.lock`.

### Package version

`[project]` takes an optional `version = "1.2.3"`: three numbers and an optional `-pre` suffix, with no leading `v`. A calendar version such as `2026.11.0` is valid and is read as semver, with the year as the major. An application leaves `version` out. A package that others depend on declares it.

The tag selects a release; the manifest `version` is only a check. At a tagged commit it must equal the tag's version, or the build fails and the error says to ask the author to fix the tag or to require an earlier version. A tag that does not look like a version cannot be chosen by `version`, and a pinned tag is not checked.

### Resolution

Packages can depend on packages. The resolver follows Cargo: it reads the requirements of the project and of every package it picks, and builds one copy of each repository for each compatible range.

Two packages that ask for `^1.2` and `^1.4` of one repository share one copy, the highest tag that satisfies both. A requirement on the next major (`^2`) gets another copy, and `0.4.x` and `0.5.x` are separate copies. The types of two copies are different, and the checker names both versions when they meet. If no tag satisfies the requirements in a range, `ms install` names the packages that asked.

`ms.lock` has one line per copy, keyed by the repository and version, such as `github.com/acme/wire@v1.4.2`. A lock that still satisfies the requirements is kept, so a new upstream tag changes nothing until you run `ms install --update @name`. A resolved copy that declares an effect the project does not allow is an error on every build, and the message names the package and the effect.

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
import Config, open from "@pg/conn.ms"
```

- `@name/path.ms` resolves under the package's `source` directory, as a directory alias does.
- `check`, `build`, `run`, `test` and `lint` never use the network. A missing lock entry or missing cache entry is an error that says to run `ms install`. A locked build works offline.
- `ms install --update @pg` picks the version again and rewrites that entry. A tag that moved, or changed content, fails against the lock until you update it.
- Packages are cached read-only outside the project, in a directory named by the content hash: `$XDG_CACHE_HOME/ms/packages` (or `$HOME/.cache/ms/packages`, `%LOCALAPPDATA%\ms\packages` on Windows). `MS_PACKAGE_CACHE` overrides it.
- The hash is the SHA-256 of an index that lists each file's path and own SHA-256, stored beside the package. A build checks the index once and each file as it is read, so a cached file changed after the fetch is an error. `ms install` checks the cached copies it pins and fetches again any that were changed or are missing.
- Packages hash the same on every platform because these are errors: symbolic links, non-UTF-8 names, two paths that differ only by letter case, and names Windows cannot create (`a:b`, `aux`, a trailing dot or space).
- A package's own dependencies are private to it: importing `@name` there does not give the project that name. Diagnostics name a package's files `@github.com/acme/wire@v1.4.2/lib.ms`.
- A package declares what it may reach with `effects = ["std.net.*"]` under `[project]`, using the patterns of [`allow_effect`](../../core-language/functions/effects.md). Without the key it is pure.
  - The project must allow each declared effect under `[effects]`, or the package is rejected and the error names the effect.
  - The checker holds the package to its declaration. If any function in it, or in a dependency it calls, reaches an effect it did not declare, `check` and `build` fail.
  - The declaration is the default permit for the package's functions; an `allow_effect` line there can only narrow it.
  - A package cannot give a dependency effects it does not declare itself.
- Packages hold source only: no `entry`, no `[embed]`, no `extern` declarations (the checker rejects them), no build scripts. Nothing runs when a package is fetched.
- A dependency is `https://` or, for the project's own dependencies only, `file://`. A package's own dependencies must use `https://`. `ms.lock` is validated as untrusted input: 40-digit commits, 64-digit hashes, and the same URL rules.

## Workspaces

A workspace splits one repository into projects that share code and one lock file. `ms init --workspace team` creates one: a root `ms.toml`, an `app` member that imports a `greeter` library member through a path dependency, and a test in each. To write the root by hand, list the members in `ms.toml`:

```toml
[workspace]
members = ["app", "libs/*"]
```

```toml
# app/ms.toml
[project]
name = "app"
source = "src"
entry = "src/main.ms"

[dependencies]
"@util" = { path = "../libs/util" }
```

- Each member is a directory with its own `ms.toml` and a unique `[project] name`. `"libs/*"` means every child directory of `libs` that holds an `ms.toml`. Members stay inside the workspace root; there are no nested workspaces.
- A `{ path = "..." }` dependency names another member and is imported like a package: `import greet from "@util/greet.ms"`. It is never written to `ms.lock`, a member's own dependency names are private to it, and a cycle between members is an error. A member may declare `extern`, since it is your own code.
- A member follows the same effect rule as a fetched package: it declares `effects` under `[project]`, and the importing member allows them under `[effects]`.
- One `ms.lock` beside the root `ms.toml` pins every url dependency of every member. Members that name the same repository and version share one copy; two members may use one name for different packages. `ms install` installs every member; `ms add` and `ms remove` act on the member whose directory you are in.
- Run `ms run`, `ms build` and the other commands from a member, or pass its `ms.toml`. At a root with no `[project]`, `ms check`, `ms lint`, `ms fmt`, `ms verify` and `ms test` run on every member; a command that makes one program asks you to name a member. A root may also hold its own `[project]`, and then it is a member too.

## Resolving an import

Imports name an exported symbol and a path:

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
import CustomerId from "./domain/customers.ms"
import Order from "@domain/orders.ms"
```

For an import in `src/main.ms`, the first path resolves to `src/domain/customers.ms`. The second expands `@domain` and resolves to `src/domain/orders.ms`.

| Path form | Resolves to |
| --- | --- |
| `./` or `../` | Relative to the importing file's directory |
| `@std/...` | The compiler's standard library; the `@std` alias key is rejected |
| `@name/...` | Through the project's aliases; keys are `@` plus one identifier |

- A directory alias matches a whole first segment (`@domain` does not match `@domain_extra`) and appends the rest; alone it selects no module.
- A file alias selects exactly its target `.ms` file and accepts no extra segments.
- Alias targets are relative to `ms.toml`; aliases do not expand other aliases.
- Direct paths and paths under directory aliases must include `.ms`. Extensions are never inferred and directory entry files are never searched.
- Bare module names and absolute paths are not import forms. Use `/` separators.

`[aliases]` is optional. These are compile errors: missing source or entry files, invalid or unknown aliases, unresolved imports, missing or internal symbols, wildcard imports, and cyclic dependencies.

## Module identity and configuration scope

Paths are normalized and symlinks resolved to one canonical file identity per build, so importing a file by relative path, file alias, or directory alias yields one module and cycle checks cannot be bypassed. Build metadata types paths relative to the project root.

- Application paths, source directories, and aliases must resolve inside the project root after symlink resolution; escapes are compile errors.
- `@std/...` resolves only inside the pinned standard library, which cannot import application modules.
- Changes to source roots, entry, aliases, or the standard-library distribution change the module graph and build cache identity.

See [module exports and imports](../../core-language/modules/declarations.md), [the compilation pipeline](https://github.com/manuscript-lang/manuscript/blob/main/documentation/contributing/compiler/frontend/pipeline.md), and [build caches](incremental-compilation.md).
