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

`init` creates `ms.toml`, `src/main.ms`, `test.ms` and a `.gitignore` excluding the local build cache. Run the following examples from `store`. You can add aliases to the generated manifest as the project grows:

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
- All manifest paths resolve relative to the directory containing `ms.toml` (the entry is not relative to `source`).
- Only `[project]`, `[aliases]`, `[embed]`, `[dependencies]` and `[effects]` exist. Unknown or duplicate tables and keys are rejected. `ms.toml` is TOML: strings are quoted, effects are lists of strings (`["std.net.*"]`), and a dependency is a table (`{ url = "...", tag = "v1" }`). Keys that start with `@` are quoted.
- Application modules are found by following imports from the entry, not listed in the manifest.
- The compiler supplies the prelude and version-matched `@std` modules. To reuse other Manuscript source, use [packages](#packages).

## Embedded files

`[embed]` bakes a directory into the program. Each key is an import name written like an alias, and each value is a directory below the project root:

```toml
[embed]
"@assets" = "./assets"
```

Create `assets/message.txt` containing `hello from assets` followed by a newline. Add `import files from "@assets"` above the generated `main`, then replace its body with this fragment:

```manuscript
    tree := files()
    text := tree.read("message.txt", none).get().decode_utf8().get()
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
- `files()` returns an `EmbeddedTree` from `@std/os/tree.ms`, so `read`, `children` and `walk` work as they do on a `host_tree`. Making it costs one map entry per file; `read` copies only the file it returns.
- Paths in the tree are relative to the directory and use `/` on every platform. Entries are listed in byte order. Hidden files are included.
- Symbolic links, names that are not valid UTF-8, and names that differ only by letter case are errors. A file may be at most 16 MiB and a directory 64 MiB in total.
- The files are stored in the program as raw bytes in read-only data, alongside the program code and lookup metadata. An edited, added or removed file rebuilds the program.
- A name cannot also be an alias.

## Commands and module discovery

| Command | Behavior |
| --- | --- |
| `ms check <ms.toml>` | Check all source modules and discovered tests; validate entry when present |
| `ms build <ms.toml>` | Check, lower to MIR, generate native object code, and link the executable; requires entry |
| `ms lint <ms.toml>` | Check and lint reachable modules; libraries include all source modules and discovered tests |
| `ms test <ms.toml>` | Execute tests from entry and discovered test files; libraries include all source modules too |

`ms check ms.toml` checks every `.ms` file below `project.source`, including modules the entry does not import, plus `test.ms` and `*_test.ms` anywhere below the project root. It never runs `main` or tests and needs no native toolchain. Text output reports the number of modules checked.

Discovered source filenames and visited directory names must be valid UTF-8. Invalid names report a resolution error with a rename remedy; discovery never replaces them with another path. Excluded files and directories keep their existing discovery rules.

- Discovery skips hidden directories (such as `.ms-cache`), `vendor`, `node_modules`, and directory symlinks. Entries and imports are always followed.
- Files outside the source directory are checked only if imported, the entry, or tests.
- `ms check file.ms` checks that file and its imports only.
- `check` and `lint` also take several targets; see [analysis input selection](../implementation.md#selecting-independent-analysis-inputs).

## Library projects and copied dependencies

A library needs no placeholder `main`. `ms init --lib greeter` creates one with `src/lib.ms` and a test:

```toml
[project]
name = "graph"
source = "src"
```

`check`, `lint`, and `test` include every source module and discovered test. `run`, `build`, `emit`, and `profile` need an executable entry: add `entry = "src/main.ms"` and declare `fn main()`.

Share library code as a [package](#packages).

## Packages

A package is a library project in a git repository. Name it under `[dependencies]` with a table holding the repository `url` and either a `tag` or a full `sha`. The name is written like an alias.

```toml
[dependencies]
"@pg" = { url = "https://github.com/manuscript-lang/ms-pg.git", sha = "<40-character commit>" }

[effects]
"@pg" = ["std.net.*", "std.clock.read", "std.random.read"]
```

`ms add <url> --tag <tag>` (or `--sha <commit>`) writes the dependency into `ms.toml` and installs it; `ms remove @name` takes it out again. `ms install` downloads what `ms.toml` names. Installing downloads each package with `git`, records the commit and a content hash in `ms.lock`, and prints what each package may reach. Commit `ms.lock`.

```manuscript
import Config, open from "@pg/conn.ms"
```

- `@name/path.ms` resolves under the package's `source` directory, as a directory alias does.
- `check`, `build`, `run`, `test` and `lint` never use the network. A missing lock entry or missing cache entry is an error that says to run `ms install`. A locked build works offline.
- `ms install --update @pg` resolves the tag again and rewrites that entry. A tag that moved, or changed content, fails against the lock until you update it.
- Packages are cached read-only outside the project, in a directory named by the content hash: `$XDG_CACHE_HOME/ms/packages` (or `$HOME/.cache/ms/packages`, `%LOCALAPPDATA%\ms\packages` on Windows). `MS_PACKAGE_CACHE` overrides it.
- The hash is the SHA-256 of an index listing each file's path and own SHA-256, stored beside the package. A build checks the index once and each file as it is read, so a cached file changed after the fetch is an error. Symbolic links and non-UTF-8 names are errors.
- A package's own dependencies are private to it: importing `@name` there does not give the project that name. Two tags of one repository are two packages with different types; when they meet in one expression the error names both paths and both tags.
- A package declares what it may reach with `effects = ["std.net.*"]` under `[project]`, using the patterns of [`allow_effect`](../../core-language/functions/effects.md). Without the key it is pure. The project must allow each declared effect under `[effects]`, or the package is rejected and the error names the effect. The checker holds the package to its declaration: if any function in it, or in a dependency it calls, reaches an effect it did not declare, `check` and `build` fail. The declaration is the default permit for the package's functions; an `allow_effect` line there can only narrow it. A package cannot give a dependency effects it does not declare itself.
- Packages hold source only: no `entry`, no `[embed]`, no `extern` declarations (the checker rejects them), no build scripts. Nothing runs when a package is fetched.
- A dependency is `https://` or, for the project's own dependencies only, `file://`. A package's own dependencies must use `https://`. `ms.lock` is validated as untrusted input: 40-digit commits, 64-digit hashes, and the same URL rules.

## Resolving an import

Imports name an exported symbol and a path:

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

`[aliases]` is optional. Missing source or entry files, invalid or unknown aliases, and unresolved imports are compile errors, as are missing or internal symbols, wildcard imports, and cyclic dependencies.

## Module identity and configuration scope

Paths are normalized and symlinks resolved to one canonical file identity per build, so importing a file by relative path, file alias, or directory alias yields one module and cycle checks cannot be bypassed. Build metadata types paths relative to the project root.

- Application paths, source directories, and aliases must resolve inside the project root after symlink resolution; escapes are compile errors.
- `@std/...` resolves only inside the pinned standard library, which cannot import application modules.
- Changes to source roots, entry, aliases, or the standard-library distribution change the module graph and build cache identity.

See [module exports and imports](../../core-language/modules/declarations.md), [the compilation pipeline](https://github.com/manuscript-lang/manuscript/blob/main/documentation/contributing/compiler/frontend/pipeline.md), and [build caches](incremental-compilation.md).
