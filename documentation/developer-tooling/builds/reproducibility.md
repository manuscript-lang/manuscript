+++
title = "Build pins and reproducibility"
weight = 3
+++

# Build pins and reproducibility

A reproducible build records which inputs and tool versions produced it. Those inputs include source, relevant `ms.toml` settings, the compiler and runtime, the Go toolchain, adapters, and dependencies. The [project manifest](project-configuration.md) chooses the entry file, source directory, and import aliases.

Pin the Go toolchain, compiler-supplied standard-library modules and their content identity, runtime, native adapters, and their dependencies. `@std` resolves only to that pinned distribution; a build does not fetch or silently substitute a newer library. Include this identity in module, analysis, and generated-code caches. Debug builds also pin the supported Delve version.

Generate deterministic symbol names and declaration order; do not rewrite unchanged output. This promises stable generated source for the same inputs. Byte-identical binaries need a separate toolchain and environment contract.

Choose optimization and debugging settings with [build levels](build-levels.md).

## Build identity

Build metadata records `format: 1`, `compiler`, `implementation_sha256`, and `toolchain`. The digest covers the sorted compiler, frontend, and embedded runtime sources (not tests or checkout paths). The toolchain entry records the Go version, OS and architecture, CGO, experiments, and architecture tuning from the embedded build payload.

The payload is extracted into a cache keyed by its content hash and supplies its own `GOROOT`. Native commands ignore ambient Go configuration, use private caches under `MANUSCRIPT_CACHE_DIR` (or the OS user cache), and force the bundled `GOROOT`, `GOENV=off`, `GOTOOLCHAIN=local`, `GOWORK=off`, offline modules, and `CGO_ENABLED=0`. There is no external-toolchain override or PATH fallback. Flags come from the [build level](build-levels.md).

Check, format, inspect, and emit do not need the native toolchain. There is no project lock file: the `ms` binary supplies the compiler, runtime, and toolchain. Runtime dependencies and the embedded Delve version are pinned in `go.mod` and `go.sum` and vendored with their notices; macOS's system `debugserver` remains an external prerequisite. Pinning Delve keeps the transport aligned with [debugger integration](../debugging/debugger-integration.md).

## Artifacts

`ms` keeps no executable cache; builds write straight to their output. A build's identity covers the generated source, module and configuration hashes, implementation content, target and toolchain, and build type. `<executable>.ms-build.json` carries `build_type`, the source and configuration hashes, and the executable identity; `debug` is true only for unoptimized Debug builds, which also record the source root. `compiler.VerifyBuild` rejects a mismatched binary or source snapshot before interpreting source. This pins generation and artifact identity; byte-identical binaries across environments are not promised.

Build identity travels with [debug and trace metadata](../debugging/metadata.md). See [incremental compilation](incremental-compilation.md) for caching.
