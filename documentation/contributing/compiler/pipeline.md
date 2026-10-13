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
| Optimize | `lower` | Boolean folding that keeps effects | Optimization facts beside the AST |
| Lower | `lower` | Evaluation order, cleanup on every exit, defaults, call shape | Go syntax tree, one printer |
| Build | `build` | Toolchain, pins, cache identity | Native artifact |

Canonicalization has three homes. Module and path identity is canonical after `frontend`. Types are canonical after `checker` resolves them to `checker.Type` with a `TypeKey`. Call shape (argument order, resolved labels, defaults, optional wrapping, error-source wrapping) is canonical in `checker.Info.Arguments`, `OptionalArgument`, and `ErrorSource`, but `lower` still applies it expression by expression.

Consumers read the checked program only through `Program` methods. The tables behind them are private so their storage can change.

## The gap

`lower` still receives the AST plus checked facts and re-derives structure while it emits Go: it matches on `syntax.Kind`, then consults `Info` for each case. That mixes three concerns in about 2,100 lines: desugaring (defaults, `try`, `match`, cleanup, method dispatch), optimization, and Go emission. Optimization cannot see desugared structure, and emission cannot be tested without a source program.

## Core IR

A typed, desugared core IR (`pkg/ir`) sits between `checker` and `lower`:

- Every node carries its resolved `checker.Type`. No node refers to a `syntax` node for meaning; a position is kept only for diagnostics, source maps, and fault sites.
- Names are resolved to bindings and symbols. Method calls are resolved to a selected implementation or a dynamic contract call.
- Defaults are expanded, arguments are in evaluation order, `try` and error-source conversions are explicit, `match` arms carry their binding variables, and cleanup is an explicit scope with its exit paths.
- `optimize` rewrites IR and `lower` prints it. Tooling stays on the AST and `Program` queries, because it needs every source node.

Elaboration is the one step that reads both the AST and `Program`. After it, nothing in `ir`, `optimize`, or `lower` imports `syntax` for semantics.

## Migration order

Each step merges on its own and keeps observable behavior; generated Go need not be byte-identical.

1. Define `ir` nodes and elaborate expressions that need no cleanup or match: literals, names, calls, member access, collections, text, unary and binary operations.
2. Move the boolean fold from `optimize` onto IR.
3. Elaborate statements, `match`, `try`, and defaults.
4. Elaborate cleanup scopes and function bodies; remove `lower`'s reads of `Program` tables.
5. Replace the table storage behind `Program` where the IR no longer needs it.

The `tests/e2e` programs and the lowering tests establish that behavior is unchanged.
