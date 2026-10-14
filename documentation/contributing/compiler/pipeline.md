+++
title = "Pipeline and passes"
weight = 0
+++

# Pipeline and passes

One syntax tree flows through the compiler. Each pass reads the tree and annotates it; none builds a second tree. A node carries the checker's facts in its `Fact` field, so a checked tree is self-sufficient: lowering and tooling need no side tables.

## Passes

| Pass | Package | Decides | Writes on the tree |
| --- | --- | --- | --- |
| Resolve modules | `frontend`, `project` | Canonical module identity, import cycles, overlays | `frontend.Graph` of trees in dependency order |
| Parse | `lexer`, `parser` | Layout, structure, positions | `syntax.Module` trees, strict or recovered |
| Check | `checker` | Symbols, nominal types, bounds, generic arguments, selected implementations, flow, captures, cleanup | `checker.Info` on expressions, bindings on patterns, statements, arms, and declarations, resolved types on written types |
| Fold constants | `checker` (`pass_fold.go`) | Bool constants, keeping effects | `Info.Folded` and `Info.Constant` |
| Order arguments | `checker` (`pass_arguments.go`) | Every call's arguments in written order with labels resolved | `Info.Arguments` |
| Mark plain `try` | `checker` (`pass_try.go`) | Statements whose whole value is a `try` that can return early | statement facts, read through `Program.PlainTry` |
| Summarize effects | `checker` | Reads, writes, and cleanup per function | `Program.Effects` |
| Lower | `lower` | Evaluation order, cleanup on every exit, defaults, call shape | Go syntax tree, one printer |
| Build | `build` | Toolchain, pins, cache identity | Native artifact |

Canonicalization has three homes. Module and path identity is canonical after `frontend`. Types are canonical after `checker` resolves them to `checker.Type` with a `TypeKey`. Call shape (argument order, resolved labels, optional wrapping, error-source wrapping) is canonical in `checker.Info.Arguments`, `OptionalArgument`, and `ErrorSource`; lowering reads `Info.Arguments` for every call.

Consumers read the checked tree through `Program` methods (`Info`, `PatternBinding`, `TypeReference`, and the iterators that walk its modules), so where a fact is stored can change without touching them.

## Checking each module once

A module is checked once, and its tree keeps the result. Bundled standard modules with source bodies are checked lazily: the first program that imports one (or tooling that describes the whole library) checks it and the bundled modules it imports, under a lock, and every later program shares that tree, its symbols, and its methods. Native standard declarations are resolved when the registry loads. A program checks only the modules the caller passed in. Shared trees are never written after their one check, so concurrent compiles do not race.

Identities generated while checking a bundled module carry a `standard_<module>_` prefix and number from zero per module, so they are the same in every run and never collide with a program's own.

## Adding a pass

A pass is a function over `[]*syntax.Module` that reads facts and writes new ones on the node. Put it in its own file beside the stage it follows, give its output a field on the existing fact (as `pass_fold.go` does), and run it from `check` for the modules it checked. Tooling that needs the tree as written must not depend on a pass that rewrites syntax; passes here only annotate.

## Next structural steps

- Move default expansion into a pass. Source defaults already expand in the callee's prologue; native defaults still build their closures in `lower`, and native generic expression defaults are rejected by the checker until they have a substitution design.
- Split `lower` by form once the passes leave it only emission.

The `tests/e2e` programs and the lowering tests establish that behavior is unchanged.
