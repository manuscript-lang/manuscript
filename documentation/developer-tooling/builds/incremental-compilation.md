+++
title = "Build caches"
weight = 4
+++

# Build caches

Executables are not cached. Go reuses compiled runtime packages while `ms` rebuilds the application, and recorded compile and link commands skip most of the go command's own work.

## Current build path

Native builds share a workspace: an immutable Go module containing the embedded runtime as its own package and the vendored dependencies. It is published once per runtime and dependency content beneath `manuscript/workspaces` in the user cache, so edits never rewrite the dependency tree and every build level, including Debug, reuses compiled runtime packages through Go's package cache. Each application is written to `apps/<content hash>/main.go` in that module; directories unused for an hour are removed. `ms emit` still produces one standalone file containing the runtime.

The first build of each build level runs `go build` with command tracing and records the compile and link invocations for the application package, keyed by toolchain, target, and build level. Later builds whose generated source has the same Go imports run those two tools directly, skipping the go command's dependency loading and staleness hashing. A replay requires every recorded package archive to remain in Go's cache; a missing archive, changed imports, or any tool failure falls back to `go build`, which refreshes the record. Replayed executables omit the go command's internal build IDs; artifact identity remains in build metadata.

`ms` stores no built executables: `build` writes the output, and `run`, `test`, `debug`, and `profile` build into a temporary directory removed afterwards. Reuse comes from the shared native workspace, Go's package cache, and the replay profiles below, which live in the operating system's user cache directory. `MANUSCRIPT_CACHE_DIR` overrides that root, including the bundled toolchain cache. Earlier versions wrote executables to a project `.ms-cache` (or beside a standalone `-o` output); `ms` no longer reads or removes them, so delete any that remain.

Every invocation parses, checks, and lowers source, then builds a fresh executable, so source edits, invalid source, and mismatched project pins can never run an old executable. Build metadata records compiler/runtime inputs, toolchain/target, build level, generated source, project configuration, source contents, and the executable hash; debuggable artifacts also include the source root in their identity.

`run --watch` and `test --watch` keep one process across rebuilds, so standard declarations, the toolchain query, and implementation digests are computed once. Every rebuild still needs Go application compilation and linking; linking the runtime and its dependencies dominates the remaining time. The first build of each runtime variant and build level compiles that runtime. The first build with an empty Go cache also compiles runtime dependencies; first use of a release binary extracts its bundled SDK, and first use of a runtime publishes its workspace. These cold paths are not instant.

## Further frontend caching

Frontend caching remains design work. Cache parsing, checking, and module summaries by source, relevant project configuration, and dependency identity. Use canonical resolved file identity for modules; imports through different path spellings or aliases share a module summary.

Runtime, adapter schemas, and native adapters compile as separate packages. Native adapters and the application import schemas; schemas never import either. Adapter interfaces cannot use application types. Changing application code rebuilds its package; multiple generated files do not create independent compilation units. [Go build documentation](https://pkg.go.dev/cmd/go)

See [project configuration](project-configuration.md), [the pipeline](../../contributing/compiler/frontend/pipeline.md), and [deterministic generation](reproducibility.md).
