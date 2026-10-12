+++
title = "Build caches"
weight = 4
+++

# Build caches

Unchanged native runs reuse a verified executable. After a source edit, Go can reuse compiled runtime packages while rebuilding the application. These are separate cache boundaries.

## Current build path

Native builds share a workspace: an immutable Go module containing the embedded runtime as its own package and the vendored dependencies. It is published once per runtime and dependency content beneath `manuscript/workspaces` in the user cache, so edits never rewrite the dependency tree and every build level, including Debug, reuses compiled runtime packages through Go's package cache. Each application is written to `apps/<content hash>/main.go` in that module; directories unused for an hour are removed. `ms emit` still produces one standalone file containing the runtime.

The first build of each build level runs `go build` with command tracing and records the compile and link invocations for the application package, keyed by toolchain, target, and build level. Later builds whose generated source has the same Go imports run those two tools directly, skipping the go command's dependency loading and staleness hashing. A replay requires every recorded package archive to remain in Go's cache; a missing archive, changed imports, or any tool failure falls back to `go build`, which refreshes the record. Replayed executables omit the go command's internal build IDs; artifact identity remains in build metadata.

Programs that import none of `@std/net.ms`, `@std/http.ms`, `@std/tls.ms`, `@std/websocket.ms`, `@std/system.ms`, or `@std/process.ms`, directly or through other standard modules, link a lean runtime built with the `ms_lean` Go tag. It omits those modules' implementations and their `net/http`, `crypto/tls`, and gopsutil dependencies, which roughly halves the linker's input. Values of those modules' types can only come from their own functions, so a lean program cannot reach the omitted code. Runtime files that implement them carry `//go:build !ms_lean`; `TestLeanRuntimeImplementsLeanModules` verifies that the lean runtime registers every function and receiver method of the remaining modules.

Project commands store native artifacts in the project's `.ms-cache`. Standalone `run`, `test`, `debug`, and `profile` commands use `manuscript/artifacts` beneath the operating system's user cache directory. `MANUSCRIPT_CACHE_DIR` overrides that user cache root, including the bundled toolchain cache and native workspaces. Standalone `build` stores artifacts beside its output in `.ms-cache`. A built executable is published to the cache and its output by hard link where the file system permits.

Every invocation parses, checks, and lowers source before looking up a native artifact. Cache hits verify compiler/runtime inputs, toolchain/target, build level, generated source, project configuration, source contents, and executable hashes. Source edits, invalid source, mismatched project pins, and corrupt artifacts cannot silently run an old executable. Debuggable artifacts also include the source root in their identity.

`run --watch` and `test --watch` keep one process across rebuilds, so standard declarations, the toolchain query, and implementation digests are computed once. An unchanged run avoids native compilation and linking. An edited program still needs Go application compilation and linking; linking the runtime and its dependencies dominates the remaining time. The first build of each runtime variant and build level compiles that runtime. The first build with an empty Go cache also compiles runtime dependencies; first use of a release binary extracts its bundled SDK, and first use of a runtime publishes its workspace. These cold paths are not instant.

## Further frontend caching

Frontend caching remains design work. Cache parsing, checking, and module summaries by source, relevant project configuration, and dependency identity. Use canonical resolved file identity for modules; imports through different path spellings or aliases share a module summary.

Runtime, adapter schemas, and native adapters compile as separate packages. Native adapters and the application import schemas; schemas never import either. Adapter interfaces cannot use application types. Changing application code rebuilds its package; multiple generated files do not create independent compilation units. [Go build documentation](https://pkg.go.dev/cmd/go)

See [project configuration](project-configuration.md), [the pipeline](../../contributing/compiler/frontend/pipeline.md), and [deterministic generation](reproducibility.md).
