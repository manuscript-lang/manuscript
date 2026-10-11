+++
title = "Pinned dependencies and deterministic output"
weight = 99
+++

# Pinned dependencies and deterministic output

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A build’s identity includes the source, relevant `ms.toml` settings, toolchain, runtime, adapters, and dependencies used to produce it. The [project manifest](project-configuration.md) establishes the entry file, source directory, and optional import aliases.

Pin the Go toolchain, compiler-supplied standard-library modules and their content identity, runtime, native adapters, and their dependencies. `@std` resolves only to that pinned distribution; a build does not fetch or silently substitute a newer library. Include this identity in module, analysis, and generated-code caches. Debug builds also pin the supported Delve version.

Generate deterministic symbol names and declaration order; do not rewrite unchanged output. This promises stable generated source for the same inputs. Byte-identical binaries need a separate toolchain and environment contract.

## Details still needed

The lock format and its creation/update commands are unspecified. Define required versions and content checksums, transitive native dependencies, target and build flags, and the behavior on missing or mismatched pins. Ordinary builds must not silently choose new dependency versions.

Pinning Delve keeps the native transport contract aligned with [debugger integration](../../developer-tooling/debugging/debugger-integration.md).

Build identity and source hashes must travel with [debug and trace metadata](../../developer-tooling/debugging/metadata.md). See [incremental compilation](incremental-compilation.md) for caching and package boundaries.

[Previous: Project configuration and module paths](project-configuration.md) · [Next: Caching and Go package boundaries](../builds/incremental-compilation.md)
