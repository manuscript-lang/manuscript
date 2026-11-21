# src/compiler/project

Layer L3a: file names to the module graph the checker reads (`project.h`): paths, ms.toml, imports, packages,
the bundled standard-library sources. Allowed includes: see `src/layers.txt`.

Landed: `ms_project_load` for a standalone `.ms` file and its local (`./`, `../`) imports, with the Rust
loader's error texts, cycle detection and unsaved-editor overlays (`load.c`, `resolve.c`, `project.c`), and the
bundled standard library (`cmake/EmbedStdlib.cmake` generates `std_embedded.c` from `stdlib/`).

Not yet: ms.toml (aliases, embeds, `[project]`), packages, `tests` discovery, editor recovery with several
parse diagnostics per file (a syntax error stops the load at the first), and the case check on macOS and
Windows. A manifest above the file is ignored, so an `@alias` import reports "unknown import alias".
