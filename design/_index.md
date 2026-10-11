+++
title = "Overview"
weight = 1
+++

# Manuscript design guide

Manuscript is a statically typed language for teams where AI writes code and humans review system boundaries, execution flows, and changes. It uses explicit data, ordinary functions, concurrency APIs, and scoped resource cleanup. The compiler is written in Go and generates Go.

The whole guide describes Manuscript 0.1. A working compiler, runtime, CLI, and native conformance suite live in this repository; see [implementation coverage](https://github.com/manuscript-lang/manuscript/blob/main/IMPLEMENTATION.md) for the supported surface and verification commands. Rules describe required behavior. Examples become implementation evidence when corresponding tests execute them; declaration-only fixtures establish acceptance, not runtime behavior. Pages that still need API or tooling decisions name those gaps explicitly.

## Design constraints

- One canonical syntax and formatter.
- Explicit public contracts; inferred local types.
- One module per `.ms` file; path imports and optional aliases configured in project-root `ms.toml`.
- A small intrinsic prelude; standard facilities are explicit `@std/...ms` imports.
- Every supplied function argument is named.
- One function kind. Every function can suspend.
- Sequential execution unless concurrency is explicitly started.
- Expected failures are values.
- Concurrent work has a fixed lifetime and explicit cancellation.
- Lexical `with` cleanup calls `Closeable.close()` on registered resources.
- Architecture and flow diagrams derive from typed source.
- External dependencies enter through explicit parameters.

## Design guides

| Guide | Concerns |
| --- | --- |
| [Core language](core-language/_index.md) | Chaptered language guide: basics, data modeling, functions, control flow, and errors |
| [Standard library](standard-library/_index.md) | Type catalog, parallel mapping, background services, streams, queues, state, builders, and hosts |
| [Resource lifetimes and cleanup](ownership-and-cleanup/_index.md) | Ordinary references, runtime closed-state checks, and lexical resource release |
| [Concurrency](concurrency/_index.md) | Parallel operations, background work, joining, cancellation, and deadlines |
| [Modules and capabilities](modules-and-capabilities/_index.md) | Module boundaries, explicit authority, inferred effects, and Go adapter contracts |
| [Compiler design](compiler/_index.md) | Compilation pipeline, type, scope, and capture checking, Go lowering, builds, and conformance |
| [Developer tooling](developer-tooling/_index.md) | Generated diagrams, structural edits, formatting, debugging, and trace metadata |

Start with the core language, then follow the guides for resources, concurrency, boundaries, and implementation. [Scope and implementation order](compiler/conformance/scope.md) collects outstanding decisions and required evidence.

A concept page owns its rules. Other pages explain how those rules apply and link back to them. Local statements shown outside a function are body fragments; examples marked rejected are independent negative cases. Body fragments and isolated type expressions may omit imports; assume the individual standard imports listed in [standard API typing](standard-library/types/prelude.md). Complete application modules and conformance fixtures include their imports. Blocks describing standard declarations specify the library module itself, rather than application redeclarations. The conformance pages collect complete modules and observable expectations.

## Design review

The [language completeness review](reviews/language-completeness.md) and [Claude Code review](reviews/claude-design-review.md) retain the history of earlier findings and fixes. Their original reports describe older drafts; current concept pages govern behavior. Outstanding work is collected in [scope](compiler/conformance/scope.md#outstanding-decisions).
