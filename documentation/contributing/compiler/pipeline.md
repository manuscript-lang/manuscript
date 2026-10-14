+++
title = "Pipeline and core IR"
weight = 0
+++

# Pipeline and core IR

Each stage owns one decision, produces one value, and hands later stages facts instead of spellings. This page says where each decision is made and where the next structural step goes.

## What each stage decides

| Stage | Package | Decides | Produces |
| --- | --- | --- | --- |
| Resolve modules | `frontend`, `project` | Canonical module identity, import cycles, overlays | `frontend.Graph` of ASTs in dependency order |
| Parse | `lexer`, `parser` | Layout, structure, positions | `syntax.Module` trees, strict or recovered |
| Resolve names and types | `checker` | Symbols, nominal types, bounds, generic arguments, selected implementations | `checker.Program` queries (`Info`, `Symbol`, `TypeReference`) |
| Check flow and effects | `checker` | Reachability, captures, cleanup, mutation, effects | Flow, captures, cleanup methods, `Effects` |
| Elaborate and optimize | `ir` | Resolved performance nodes, conversion edges, storage/call eligibility, Boolean folding | Typed nodes and representation facts |
| Lower | `lower` | Translate IR facts; retain pending statement/cleanup bodies | Go syntax tree, one printer |
| Build | `build` | Toolchain, pins, cache identity | Native artifact |

Canonicalization has three homes. Module and path identity is canonical after `frontend`. Types are canonical after `checker` resolves them to `checker.Type` with a `TypeKey`. Call shape (argument order, resolved labels, defaults, optional wrapping, error-source wrapping) is canonical in `checker.Info.Arguments`, `OptionalArgument`, and `ErrorSource`, and is materialized into explicit IR use edges and call parameter slots before performance emission.

Consumers read the checked program only through `Program` methods. The tables behind them are private so their storage can change.

## The gap

`lower` still receives the AST plus checked facts and re-derives structure while it emits Go: it matches on `syntax.Kind`, then consults `Info` for each case. That mixes three concerns in about 2,100 lines: desugaring (defaults, `try`, `match`, cleanup, method dispatch), optimization, and Go emission. Optimization cannot see desugared structure, and emission cannot be tested without a source program.

## Core IR

`pkg/ir` now elaborates the expression forms and representation facts needed by
performance work: literals, bindings, primitive operations, resolved calls,
match-value edges, Lists and typed record access. See the [shared contract](lowering/typed-ir-contract.md)
for the exact API and its backend obligations. Boolean folding uses `ir.Folder`.
Tooling retains checked source and `Program` queries.

The full body IR remains a migration target. Statement bodies, dynamic default
preparation, `try` and cleanup still cross explicit deferred boundaries. Once
those forms migrate, `lower` will no longer need checked syntax for their meaning.
Defaults are callee-owned evaluation facts, not eagerly expanded caller arguments.

## Migration order

Each step merges on its own and keeps observable behavior; generated Go need not be byte-identical.

1. Define `ir` nodes and elaborate expressions that need no cleanup or match: literals, names, calls, member access, collections, text, unary and binary operations.
2. Move the boolean fold onto IR. Done: `ir.Folder` replaces the `lower` optimizer and its `booleans` table.
3. Elaborate statements, `match`, `try`, and defaults.
4. Elaborate cleanup scopes and function bodies; remove `lower`'s reads of `Program` tables.
5. Replace the table storage behind `Program` where the IR no longer needs it.

The `tests/e2e` programs and the lowering tests establish that behavior is unchanged.
