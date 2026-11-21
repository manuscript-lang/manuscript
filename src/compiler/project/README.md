# src/compiler/project

Layer L3a: file names to the module graph the checker reads (`project.h`): paths, ms.toml, imports, packages,
the bundled standard-library sources. Allowed includes: see `src/layers.txt`. Only the header is landed so far;
the Checker codes against it while the loader is ported from crates/ms-driver.
