[Wiki](../index.md) › [Compiler and build](index.md)

# Omitted library entries must stay empty through module loading

Verified: executable manifests require an entry; libraries omit the key, and an explicitly empty or invalid entry remains an error. Resolving an empty entry as a source path would turn it into the project directory, so graph loading skips that resolution and discovers source and test roots instead. Application commands report the missing entry at the manifest's project table; source analysis and test lowering use the same graph without requiring `main`.


Apply when: changing manifest modes, project discovery, editor overlays, or entry validation.
Evidence: [manifest parsing](../../crates/ms-driver/src/project/manifest.rs), [library regressions](../../crates/ms-driver/tests/project_library.rs), [graph loading](../../crates/ms-driver/src/load.rs), [library contracts](../../documentation/developer-tooling/builds/project-configuration.md#library-projects-and-copied-dependencies).
Verify: an omitted entry checks unimported modules and executes their tests; an explicit bad entry still fails (`cargo nextest run -p ms-driver`).
