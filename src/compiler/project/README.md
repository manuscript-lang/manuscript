# src/compiler/project

Layer L3a: file names to the module graph the checker reads (`project.h`): paths, ms.toml, imports, packages,
the bundled standard-library sources. Allowed includes: see `src/layers.txt`.

Landed: `ms_project_load` for a `.ms` file, an `ms.toml` or the nearest `ms.toml` above a file: local (`./`,
`../`) and `@alias` imports, the Rust loader's error texts, cycle detection and unsaved-editor overlays
(`load.c`, `resolve.c`, `project.c`), the manifest reader for `[project]` (name, source, entry), `[aliases]` and
`[embed]` (`manifest.c`, with the TOML subset in `toml.c`), and the bundled standard library
(`cmake/EmbedStdlib.cmake` generates `std_embedded.c` from `stdlib/`).

Also landed: `[embed]` directories as generated modules (`embed.c`), and module discovery for libraries and
`ms check` (`discover.c`). Unsaved editor files are not added to discovery.

Not yet: `tests` discovery of editor files, `[dependencies]`, `[effects]`, `[workspace]`, `version`, packages, full
TOML (arrays, inline tables, dotted keys, multi-line strings) with toml_edit's error wording, editor recovery with
several parse diagnostics per file (a syntax error stops the load at the first), and the case check on macOS and
Windows.
