+++
title = "Build pins and reproducibility"
weight = 3
+++

# Build pins and reproducibility

A reproducible build records which inputs and tool versions produced it. Those inputs include source, relevant `ms.toml` settings, the compiler and runtime, the Go toolchain, adapters, and dependencies. The [project manifest](project-configuration.md) chooses the entry file, source directory, and import aliases.

Pin the Go toolchain, compiler-supplied standard-library modules and their content identity, runtime, native adapters, and their dependencies. `@std` resolves only to that pinned distribution; a build does not fetch or silently substitute a newer library. Include this identity in module, analysis, and generated-code caches. Debug builds also pin the supported Delve version.

Generate deterministic symbol names and declaration order; do not rewrite unchanged output. This promises stable generated source for the same inputs. Byte-identical binaries need a separate toolchain and environment contract.

Choose optimization and debugging settings with [build levels](build-levels.md).

## Details still needed

A project build that finds no `ms.lock` creates it automatically; an existing pin that no longer matches still fails until `ms lock ms.toml` explicitly creates or updates project-root `ms.lock`, a JSON object with closed fields: `format: 1`, `compiler: "0.1.0"`, `implementation_sha256`, and `toolchain`. The implementation digest covers sorted compiler/frontend and embedded runtime source contents, excluding tests and checkout paths. Toolchain records Go version, OS/architecture, CGO, experiments, and architecture tuning from the embedded build payload, or an explicit `MANUSCRIPT_GO` override. Pins and builds share toolchain selection. The payload is extracted into a cache identified by its content hash and supplies its own `GOROOT`. Native commands use `GOENV=off`, `GOTOOLCHAIN=local`, and `CGO_ENABLED=0`; they need no system Go or C compiler and cannot automatically download another Go version. Pinned builds require empty GOFLAGS; native flags are selected by the [build level](build-levels.md).

Project `build`, `run`, and `test` reject missing or mismatched pins and instruct the caller to explicitly run `lock`. Check/format/inspect/emit do not require a native toolchain pin. Standalone module builds record the selected toolchain without claiming a project lock. There are no third-party native dependencies in the supplied runtime. External adapter dependency pins and Delve remain separate future distribution contracts.

Native artifacts are cached under project `.ms-cache/` by generated source, original module/configuration hashes, implementation content, target/toolchain, and build type. Cache hits verify metadata and binary content hashes; corruption rebuilds. A matching output is not rewritten. `<executable>.ms-build.json` carries the canonical `build_type`, source/configuration hashes, and executable identity. `debug` remains true only for unoptimized Debug builds. Builds retaining debugging information also record the source root in their cache identity. `compiler.VerifyBuild` rejects mismatched binaries or supplied source/configuration snapshots before source interpretation. This pins source generation and artifact identity; byte-identical binary reproducibility across environments is not promised.

Pinning Delve keeps the native transport contract aligned with [debugger integration](../debugging/debugger-integration.md).

Build identity and source hashes must travel with [debug and trace metadata](../debugging/metadata.md). See [incremental compilation](incremental-compilation.md) for caching and package boundaries.
