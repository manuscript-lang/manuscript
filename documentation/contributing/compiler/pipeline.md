+++
title = "Pipeline and passes"
weight = 0
+++

# Pipeline and passes

Use this map to locate the stage responsible for a compiler bug. A rejected valid program starts in parsing or checking; a wrong result after successful checking needs its MIR and native execution compared. The checker exposes typed HIR as a query view over syntax and per-module facts, shared by lowering and tooling.

## Passes

| Pass | Crate | Decides | Writes |
| --- | --- | --- | --- |
| Resolve modules | `ms-driver` | Module identity, cycles, overlays | Module graph in dependency order |
| Parse | `ms-syntax` | Layout, structure, positions | Syntax tree, strict or recovered |
| Check | `ms-check` | Symbols, types, bounds, implementations, flow, captures, cleanup, effects, ownership | Typed HIR and diagnostics |
| Ownership | `ms-check` (`ownership`) | Moves, borrows, `var` modes, drops | Facts lowering reads |
| Lower | `ms-lower` | Evaluation order, exit cleanup, defaults, call shape | MIR |
| Optimize and verify | `ms-mir` | Inlining, copy elimination, range facts, verification | Optimized MIR |
| Generate code | `ms-clif` | Machine code, line tables | Object file |
| Link | `ms-build`, `ms-native` | Runtime and standard crates | Native executable |

Consumers go through the checker's public API (the HIR and its ownership facts), so storage can change freely. The [design contract](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md) records the crates and their order.

## Checking each module once

Each module is checked once and shared by whatever needs it. Native standard declarations resolve when the registry loads from `stdlib/*.ms`.

## Adding a pass

A pass reads facts and writes new ones; it does not rewrite the syntax tree. Put it in its own file beside the stage it follows and give its output a field on the existing facts. Tooling that needs source as written must not depend on a pass that rewrites syntax.
