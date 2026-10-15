+++
title = "Project configuration"
weight = 1
+++

# Project configuration

A project has an `ms.toml` file at its root. The compiler reads this file to locate source and the entry file and to resolve optional import aliases. Each `.ms` file is one module; no source-level `module` declaration is required or accepted.

## A project manifest

`ms init [directory]` creates a manifest, an entry module, a `test.ms`, and a `.gitignore` excluding `.ms-cache/`. Commit `ms.lock`, which the first build creates, and do not commit `.ms-cache/`.

```toml
[project]
name = "store"
source = "./src"
entry = "./src/main.ms"

[aliases]
"@domain" = "./src/domain"
"@customers" = "./src/domain/customers.ms"
```

`project.name` names the project. `project.source` identifies its source directory, and the optional `project.entry` identifies its executable entry `.ms` file. Omitting `entry` declares a library project; an explicitly empty or invalid entry is an error. There is no default entry. All filesystem paths in the manifest resolve relative to the directory containing `ms.toml`, including the entry path; the entry path is not relative to `project.source`.

## Commands and module discovery

| Command | Behavior |
| --- | --- |
| `ms check <ms.toml>` | Check all source modules and discovered tests; validate entry when present |
| `ms build <ms.toml>` | Check, generate Go, and build the executable; requires entry |
| `ms lint <ms.toml>` | Check and lint reachable modules; libraries include all source modules and discovered tests |
| `ms test <ms.toml>` | Execute tests from entry and discovered test files; libraries include all source modules too |
| `ms lock <ms.toml>` | Record compiler/runtime, bundled SDK, and target pins; valid for libraries |

A relative manifest argument resolves from the invocation directory. Its containing directory then becomes the project root for configuration paths. The entry follows the [CLI main contract](../../standard-library/cli.md).

`ms check ms.toml` checks every `.ms` file recursively below `project.source`,
including modules the entry does not import. It also checks `test.ms` and
`*_test.ms` files anywhere below the project root, matching `ms test ms.toml`
discovery. Discovery skips hidden directories (such as `.ms-cache`), `vendor`,
and `node_modules`, and does not follow directory symlinks. An explicitly selected
source directory is scanned even if its own name is hidden. Entries and imports
are always followed, including paths otherwise excluded from discovery. Files
outside the source directory are checked only if imported, selected as entry, or
named as tests. Discovered files use the manifest aliases and the same confined,
canonical module identities as imports. A traversal or source error fails the
check; successful text output reports the number of local modules checked.
Checking never executes main functions or test blocks and needs no native toolchain.

`ms check file.ms` checks that file and its imports without project-wide discovery.
Check, lint, and doc also accept independent target collections and standalone
directories; see [analysis input selection](../implementation.md#selecting-independent-analysis-inputs).
Their collection mode retains the project behavior in the table above and never
combines several applications into one native entrypoint.
For executable projects, the build and other source commands discover application modules by following imports from entry. The manifest does not enumerate them. Only `[project]` and `[aliases]` are implemented; unknown tables, unknown project keys, duplicate tables, and duplicate keys are rejected. Values must be double-quoted strings. Comments begin with `#` outside a quoted string.

The compiler rejects external `[adapters]` tables; external adapters are not implemented.

The compiler supplies the minimal intrinsic prelude and the standard modules under `@std`. Third-party Manuscript packages are unsupported; native dependencies follow [build pinning](reproducibility.md).

## Library projects and copied dependencies

A library needs no placeholder `main`:

```toml
[project]
name = "graph"
source = "src"
```

`ms check ms.toml`, `ms lint ms.toml`, and `ms test ms.toml` include every source module and discovered test file, even when no other module imports them. The discovery exclusions above still apply. `ms lock ms.toml` records build pins for library tests. `run`, `build`, `emit`, `debug`, and `profile` require an executable entry; add `entry = "src/main.ms"` under `[project]` and export `fn main() -> Int` from that file to make an executable.

To share library code today, copy its sources into each consuming project, for example `src/graph/`, and use relative imports or an alias:

```toml
[aliases]
"@graph" = "src/graph"
```

Keep the copied sources under version control. Alongside the copy, record the upstream URL and exact revision, SHA-256 checksums of the copied files, and the upstream license and notices. Preserve relative imports and configure any aliases used by those sources in the consuming manifest. Update the copy deliberately from a chosen upstream revision and review its changes and checksums. This is a manual copy workflow; the compiler does not fetch packages or verify these recorded checksums.

`ms.lock` pins the compiler/runtime and standard declarations through their implementation identity, the bundled Go SDK, and the target. It does **not** pin copied Manuscript package content. Native artifact metadata hashes the source modules actually checked for a build, so editing a library module invalidates its test artifact; that cache identity is not a package lock. An alias to a sibling project or an external symlink remains rejected after canonical path resolution. Alias definition errors point at the key; invalid targets point at the value in `ms.toml`.

## Resolving an import

Imports name an exported symbol and a path:

```manuscript
import CustomerId from "./domain/customers.ms"
import Order from "@domain/orders.ms"
```

For an import in `src/main.ms`, the first path resolves to `src/domain/customers.ms`. The second expands `@domain` using the manifest and resolves to `src/domain/orders.ms`.

- A path beginning with `./` or `../` resolves relative to the importing file's directory.
- A path beginning with `@std/` resolves within the compiler-supplied standard-library directory. `@std` alone selects no module. The `[aliases]` key `@std` is rejected, so an application cannot override standard identities.
- Other paths beginning with `@` resolve through the importing project's aliases. Alias keys consist of `@` followed by one identifier, such as `@domain`.
- A directory alias matches its complete first path segment and appends the remaining path. `@domain` does not match `@domain_extra`. A directory alias alone does not select a module.
- A file alias selects exactly its target `.ms` file and accepts no appended path segments.
- Alias targets are filesystem paths relative to `ms.toml`; aliases do not expand other aliases.
- Direct paths and paths appended to directory aliases must include `.ms`. Resolution does not infer extensions or search for directory entry files. A file alias can omit the extension in the import because its configured target supplies it.
- Bare logical module names and absolute filesystem paths are not import forms. Paths use `/` as the separator.

`[aliases]` is optional. Ordinary relative imports work without it. Missing source directories or entry files, invalid alias definitions, unknown aliases, and imports that do not resolve to an existing `.ms` file are compile errors. Import checking also rejects missing or internal symbols, wildcard imports, and cyclic module dependencies.

## Module identity and configuration scope

The compiler normalizes resolved paths, including `.` and `..`, and resolves symbolic links to establish one canonical file identity within a build. Importing the same file through a relative path, a file alias, or a directory alias does not create separate modules. Cycle detection and module caching use this identity, so alternate path spellings cannot bypass cycle checks. Stable build metadata records paths relative to the owning project root rather than checkout-specific absolute paths.

Application paths, source directories, user aliases, adapter manifests, and interface modules must resolve inside the project root after symlink resolution. Escapes are compile errors. `@std/...ms` is the sole exception: paths resolve inside the pinned standard-library directory, and normalization/symlinks cannot escape that directory or reach application files. Standard module identity is its distribution version/content identity plus canonical distribution-relative path, independent of its installation location. Standard modules cannot import application modules.

Interfaces may use intrinsic types and import standard declarations or other registered interfaces, never application modules. Native Go dependencies are pinned adapter inputs. External Manuscript dependency projects and package acquisition syntax are unsupported.

Changes to source roots, entry files, aliases, or the pinned standard-library distribution can change the resolved module graph. The compiler includes relevant manifest settings in build and analysis cache identity, alongside source and dependency identities.

See [module exports and imports](../../core-language/modules/declarations.md), [the compilation pipeline](../../contributing/compiler/frontend/pipeline.md), and [incremental compilation](incremental-compilation.md).
