# src/compiler/project

Layer L3a: file names to the module graph the checker reads (`project.h`): paths, ms.toml, imports, packages,
the bundled standard-library sources. Allowed includes: see `src/layers.txt`.

Landed: `ms_project_load` for a `.ms` file, an `ms.toml` or the nearest `ms.toml` above a file: local (`./`,
`../`) and `@alias` imports, the Rust loader's error texts, cycle detection and unsaved-editor overlays
(`load.c`, `resolve.c`, `project.c`), the manifest reader for `[project]` (name, source, entry), `[aliases]` and
`[embed]` (`manifest.c`, with the TOML subset in `toml.c`), and the bundled standard library
(`cmake/EmbedStdlib.cmake` generates `std_embedded.c` from `src/stdlib/`).

Also landed: `[embed]` directories as generated modules (`embed.c`), and module discovery for libraries and
`ms check` (`discover.c`). Unsaved editor files are not added to discovery.

Also landed: several parse diagnostics per file (`ms_parse_partial` in the syntax library), the manifest tables
`[dependencies]` (git and path entries), `[effects]` and `[workspace]`, `[project]` `version` and `effects`
(`manifest_packages.c`), semantic versions and requirements (`semver.c`), dependency specs (`package.c`), TOML arrays
and one-line inline tables, and workspace members with `fmt` on workspace roots (`workspace.c`).

Not yet: `tests` discovery of editor files, the lock file, the package cache and git fetch, packages in import
resolution, dotted keys, `[dependencies.name]` tables and multi-line strings in TOML (and toml_edit's error wording),
`check` over several targets (a workspace root), and the case check on macOS and Windows.
