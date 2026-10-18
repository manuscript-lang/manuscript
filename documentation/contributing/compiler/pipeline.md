+++
title = "Pipeline and passes"
weight = 0
+++

# Pipeline and passes

One syntax tree flows through the compiler. Passes annotate it and build no second tree; each node's `Fact` field carries checker facts, so lowering and tooling need no side tables.

## Passes

| Pass | Package | Decides | Writes |
| --- | --- | --- | --- |
| Resolve modules | `frontend`, `project` | Module identity, cycles, overlays | `frontend.Graph` in dependency order |
| Parse | `lexer`, `parser` | Layout, structure, positions | `syntax.Module`, strict or recovered |
| Check | `checker` | Symbols, types, bounds, implementations, flow, captures, cleanup | `checker.Info`, pattern bindings, resolved types |
| Fold constants | `checker` (`pass_fold.go`) | Bool constants, keeping effects | `Info.Folded`, `Info.Constant` |
| Order arguments | `checker` (`pass_arguments.go`) | Arguments in written order, labels resolved | `Info.Arguments` |
| Mark plain `try` | `checker` (`pass_try.go`) | Statements that are a `try` able to return early | `Program.PlainTry` |
| Summarize effects | `checker` | Reads, writes, cleanup per function | `Program.Effects` |
| Lower | `lower` | Evaluation order, exit cleanup, defaults, call shape | Go syntax tree, one printer |
| Build | `build` | Toolchain, pins, cache identity | Native artifact |

Canonical forms: module and path identity after `frontend`; types as `checker.Type` with a `TypeKey` after `checker`; call shape in `Info.Arguments`, `OptionalArgument`, and `ErrorSource`, which lowering reads for every call. Consumers go through `Program` methods (`Info`, `PatternBinding`, `TypeReference`, module iterators), so storage can change freely.

## Checking each module once

- Each module is checked once and its tree keeps the result.
- Bundled standard modules with source bodies check lazily under a lock on first import (or whole-library tooling), then every program shares the tree, symbols, and methods. Native standard declarations resolve when the registry loads.
- A program checks only modules the caller passed in. Shared trees are never rewritten, so concurrent compiles do not race.
- Identities generated for a bundled module carry a `standard_<module>_` prefix and number from zero per module, so they are stable and never collide.

## Adding a pass

A pass is a function over `[]*syntax.Module` that reads facts and writes new ones on the node. Put it in its own file beside the stage it follows, give its output a field on the existing fact, and run it from `check`. Passes only annotate; tooling that needs source as written must not depend on one that rewrites syntax.

## Next structural steps

- Move default expansion into a pass. Source defaults expand in the callee prologue; native defaults still build closures in `lower`, and the checker rejects native generic expression defaults until they have a substitution design.
- Split `lower` by form once passes leave it only emission.
