+++
title = "Project configuration"
weight = 1
+++

# Project configuration

A project has an `ms.toml` at its root that locates source and the entry file and defines import aliases. Each `.ms` file is one module; there is no `module` declaration.

## A project manifest

`ms init [directory]` creates a manifest, an entry module, a `test.ms`, and a `.gitignore` excluding `.ms-cache/`. Do not commit `.ms-cache/`.

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
- Only `[project]` and `[aliases]` exist. Unknown or duplicate tables and keys are rejected, as are `[adapters]` tables. Values are double-quoted strings; `#` starts a comment.
- Application modules are found by following imports from the entry, not listed in the manifest.
- The compiler supplies the prelude and `@std` modules. Third-party Manuscript packages are unsupported; native dependencies are pinned inside `ms` ([how it works](../how-it-works.md)).

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

A library needs no placeholder `main`:

```toml
[project]
name = "graph"
source = "src"
```

`check`, `lint`, and `test` include every source module and discovered test. `run`, `build`, `emit`, and `profile` need an executable entry: add `entry = "src/main.ms"` and export `fn main() Int`.

To share library code today, copy its sources into each consuming project, for example `src/graph/`, and use relative imports or an alias:

```toml
[aliases]
"@graph" = "src/graph"
```

Keep the copy under version control and record the upstream URL, exact revision, SHA-256 checksums, and license notices. Update it deliberately. The compiler does not fetch packages or verify those checksums, and copied content is not pinned. An alias to a sibling project or an external symlink is rejected.

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

Paths are normalized and symlinks resolved to one canonical file identity per build, so importing a file by relative path, file alias, or directory alias yields one module and cycle checks cannot be bypassed. Build metadata records paths relative to the project root.

- Application paths, source directories, aliases, and interface modules must resolve inside the project root after symlink resolution; escapes are compile errors.
- `@std/...` resolves only inside the pinned standard library, which cannot import application modules.
- Interfaces may use intrinsic types and import standard declarations or other interfaces, never application modules.
- Changes to source roots, entry, aliases, or the standard-library distribution change the module graph and build cache identity.

See [module exports and imports](../../core-language/modules/declarations.md), [the compilation pipeline](../../contributing/compiler/frontend/pipeline.md), and [incremental compilation](incremental-compilation.md).
