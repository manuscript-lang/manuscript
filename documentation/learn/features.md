+++
title = "Features and boundaries"
weight = 3
+++

# Features and boundaries

Manuscript aims to make a program's public contracts, dependencies, and work lifetimes visible in its source.

| Feature | What it gives you | Exact rules |
| --- | --- | --- |
| Static, nominal types | Distinct domain types and explicit public signatures | [Types](../core-language/types/_index.md) |
| Argument labels | Named arguments for functions with multiple parameters; optional labels for single-parameter calls | [Calls](../core-language/functions/declarations-and-calls.md) |
| Records and alternatives | Immutable data and exhaustive case handling | [Data modeling](../core-language/types/alternatives.md) |
| Expected failures as values | Typed success and error paths | [Results](../core-language/errors/results.md) |
| Explicit contracts | Conformance declared with `impl` | [Contracts](../core-language/types/contracts.md) |
| Scoped resource cleanup | `with` closes registered resources on scope exit | [Cleanup](../ownership-and-cleanup/cleanup/scopes.md) |
| Explicit concurrency | Joined work, bounded mapping, and background services | [Concurrency](../concurrency/_index.md) |
| Capability parameters | Files, clocks, network, and subprocess authority supplied by callers | [Authority](../modules-and-capabilities/capabilities/authority.md) |
| Native Go lowering | Native binaries and inspectable generated code | [Compiler](../compiler/_index.md) |

## Cleanup and work lifetimes

`with` registers resources implementing `Closeable` for lexical cleanup. The language uses garbage-collected references; cleanup concerns resource release. Retaining an alias does not extend a closed resource's usability. The [cleanup guide](../ownership-and-cleanup/_index.md) specifies exit order and cleanup faults.

`parallel` joins a literal set of operations. `Background` owns longer-lived work and shutdown. All values may be shared freely. Use [Synchronized](../standard-library/data-and-io/synchronized-state.md#synchronized) for a complete read–modify–write critical section; `with` releases its guard.

## Modules and authority

Every source file is a module. Imports select declarations, and exported declarations form the public surface. Importing `Files` does not grant filesystem access: an application receives authority through values such as `Process.files` and passes it to the functions that need it. This keeps dependencies visible and lets tests provide explicit implementations.

## Current limits

The implementation includes a compiler, runtime, native test runner, formatter, inspection output, and static diagrams. External adapters, structural editing, and debugger integration still have design work remaining. Consult [implementation coverage](https://github.com/manuscript-lang/manuscript/blob/main/documentation/implementation.md) before relying on a proposed feature.
