+++
title = "Build caches"
weight = 4
+++

# Build caches

Executables are not cached. Go reuses compiled runtime packages while `ms` rebuilds the application, and recorded compile and link commands skip most of the go command's own work.

## Current build path

- **Shared workspace.** An immutable Go module holds the embedded runtime and vendored dependencies, published once per runtime and dependency content under `manuscript/workspaces` in the user cache. Every build level reuses compiled runtime packages through Go's package cache. Each application is written to `apps/<content hash>/main.go`; directories unused for an hour are removed. `ms emit` still writes one standalone file with the runtime.
- **Replay.** The first build of each build level runs `go build` with command tracing and records the compile and link invocations, keyed by toolchain, target, and level. Later builds with the same Go imports run those tools directly. A missing archive, changed imports, or any tool failure falls back to `go build` and refreshes the record. Replayed executables omit Go's internal build IDs; identity stays in build metadata.
- **No stored executables.** `build` writes the output; `run`, `test`, `debug`, and `profile` build into a temporary directory removed afterwards. Caches live in the OS user cache directory; `MANUSCRIPT_CACHE_DIR` overrides it, including the toolchain cache. Older versions wrote executables to a project `.ms-cache` or beside `-o` output; `ms` no longer reads or removes them, so delete any that remain.
- **Always fresh.** Every invocation parses, checks, lowers, and builds a new executable, so edited or invalid source and mismatched pins never run an old binary. Build metadata records compiler and runtime inputs, toolchain, target, level, generated source, project configuration, source contents, and the executable hash; debuggable artifacts also include the source root.

`run --watch` and `test --watch` keep one process, so standard declarations, the toolchain query, and implementation digests are computed once. Each rebuild still compiles and links the application; linking the runtime dominates.

Cold paths are not instant: the first build of each runtime variant and level compiles the runtime, the first build with an empty Go cache compiles its dependencies, and first use extracts the bundled SDK and publishes the workspace.

## Further frontend caching

Frontend caching is design work: cache parsing, checking, and module summaries by source, relevant project configuration, and dependency identity, with canonical file identity so alternate path spellings share a summary.

The runtime, adapter schemas, and native adapters compile as separate packages. Adapters and the application import schemas; schemas import neither. Adapter interfaces cannot use application types. Changing application code rebuilds its package. See [Go build documentation](https://pkg.go.dev/cmd/go).

See [project configuration](project-configuration.md), [the pipeline](../../contributing/compiler/frontend/pipeline.md), and [how it works](../how-it-works.md).
