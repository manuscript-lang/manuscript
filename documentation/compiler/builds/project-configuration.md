+++
title = "Project configuration and module paths"
weight = 98
+++

# Project configuration and module paths

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A project has an `ms.toml` file at its root. The compiler reads this file to locate source and the entry file and to resolve optional import aliases. Each `.ms` file is one module; no source-level `module` declaration is required or accepted.

## A project manifest

```toml
[project]
name = "store"
source = "./src"
entry = "./src/main.ms"

[aliases]
"@domain" = "./src/domain"
"@customers" = "./src/domain/customers.ms"
```

`project.name` names the project. `project.source` identifies its source directory, and `project.entry` identifies its entry `.ms` file. All filesystem paths in the manifest resolve relative to the directory containing `ms.toml`, including the entry path; the entry path is not relative to `project.source`.

## Commands and module discovery

| Command | Behavior |
| --- | --- |
| `ms check <ms.toml>` | Check the program and its entry signature |
| `ms build <ms.toml>` | Check, generate Go, and build the executable |

A relative manifest argument resolves from the invocation directory. Its containing directory then becomes the project root for configuration paths. The entry follows the [CLI main contract](../../standard-library/hosts/cli.md).

The compiler discovers application modules by following imports from entry. The manifest does not enumerate them. Only `[project]` and `[aliases]` are implemented; unknown tables, unknown project keys, duplicate tables, and duplicate keys are rejected. Values must be double-quoted strings. Comments begin with `#` outside a quoted string.

External `[adapters]` entries and [adapter bindings](../../modules-and-capabilities/adapters/manifests.md) remain design work. The current compiler rejects those tables.

The compiler supplies the minimal intrinsic prelude and the standard modules under `@std`. Third-party Manuscript packages are unsupported; native dependencies follow [build pinning](reproducibility.md).

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

See [module exports and imports](../../modules-and-capabilities/modules/declarations.md), [the compilation pipeline](../frontend/pipeline.md), and [incremental compilation](incremental-compilation.md).

[Previous: Cleanup and fault lowering](../lowering/cleanup-and-faults.md) · [Next: Pinned dependencies and deterministic output](reproducibility.md)
