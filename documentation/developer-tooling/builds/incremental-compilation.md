+++
title = "Build caches"
weight = 4
+++

# Build caches

Unchanged native runs reuse a verified executable. After a source edit, Go can reuse compiled runtime packages while rebuilding the application. These are separate cache boundaries.

## Current build path

Native builds write the embedded runtime into a separate Go package and compile the generated application against it. Release and MinSizeRel use `-trimpath`, allowing Go's package cache to reuse the runtime across temporary build directories. Debug and RelWithDebInfo retain native source paths; their package cache reuse is more limited. `ms emit` still produces one standalone file containing the runtime.

Project commands store native artifacts in the project's `.ms-cache`. Standalone `run`, `test`, `debug`, and `profile` commands use `manuscript/artifacts` beneath the operating system's user cache directory. `MANUSCRIPT_CACHE_DIR` overrides that user cache root, including the bundled toolchain cache. Standalone `build` stores artifacts beside its output in `.ms-cache`.

Every invocation parses, checks, and lowers source before looking up a native artifact. Cache hits verify compiler/runtime inputs, toolchain/target, build level, generated source, project configuration, source contents, and executable hashes. Source edits, invalid source, mismatched project pins, and corrupt artifacts cannot silently run an old executable. Debuggable artifacts also include the source root in their identity.

An unchanged run avoids native compilation and linking. An edited program still needs Go application compilation and linking. The first build with an empty Go cache also compiles runtime dependencies; first use of a release binary extracts its bundled SDK. These cold paths are not instant.

## Further frontend caching

Frontend caching remains design work. Cache parsing, checking, and module summaries by source, relevant project configuration, and dependency identity. Use canonical resolved file identity for modules; imports through different path spellings or aliases share a module summary.

Runtime, adapter schemas, and native adapters compile as separate packages. Native adapters and the application import schemas; schemas never import either. Adapter interfaces cannot use application types. Changing application code rebuilds its package; multiple generated files do not create independent compilation units. [Go build documentation](https://pkg.go.dev/cmd/go)

See [project configuration](project-configuration.md), [the pipeline](../../contributing/compiler/frontend/pipeline.md), and [deterministic generation](reproducibility.md).
