# Receiver methods and shape-matched interfaces

## Summary
- Problem: `impl Contract for Type:` lets one type carry two same-named methods, so `close` on a `Source` plus `Sink` type is ambiguous to call and gets no scope-exit cleanup. It also indents every method.
- Change: methods are top-level `fn Type.name(...)`, one per (type, name). A type satisfies an interface when it has every operation with an exact signature; there are no `impl` blocks.
- Decision requested: approve the language change (reverses "the relationship is always declared, never inferred") and the three open questions.

## Status
Stages 1 and 2 implemented (parser; shape matching and `Closeable` by shape, `impl` still accepted), 2026-11-11. Proposal, 2026-11-10, checked against `3e2ee9ab`. Skeptical review: build only if the specialized-receiver and local-extension questions below are settled; the smallest alternative alone fixes the leak. Direction (Chinmay): methods are receiver functions like Go with implicit interface matching; the same type cannot have two methods of one name; swap `var` and `fn` (`fn var Held[T].close()`); no overlap, one function per type.

## Problem
Verified with `ms run` on `3e2ee9ab`, using `Counted` from `tests/e2e/testdata/stdlib/stream-close-once.ms` (`Source[Int]` and `Sink[Int]`, each with its own `close`):

```text
a.ms:26:11: resolution: ambiguous member close on Counted; it is provided by Sink[Int], Source[Int], so bind it to the interface first, e.g. view: Sink[Int] = value; view.close()
```
- Explicit `c.close()` is rejected; the workaround is a view. Safe, but the two bodies ("r" and "w") describe one resource released one way.
- Scope-exit cleanup needs `impl Closeable` (`closeable` in `crates/ms-check/src/contracts.rs`). `Source` and `Sink` do not extend it, so `Counted` is silently never closed (read from code, not run). That is the only demonstrated bug; the smallest alternative fixes it.
- Every method sits one level inside `impl`; 959 `impl` lines in `stdlib/`, `tests/`, `documentation/`.

## Design
```text
type Counted:
    log: String

fn var Counted.next() Int?!:
    return ok(none)

fn var Counted.write(value: Int) Unit!:
    return ok(unit)

fn var Counted.flush() Unit!:
    return ok(unit)

fn var Counted.close() Unit!:
    _ := append_file(self.log, "closed").wait()
```
(New syntax; it cannot pass `ms check` on main. Examples below are the same.)
- **Rule**: one method per (type constructor, name), declared in the type's module (as `impl Type:` today). A second declaration is a duplicate-definition error. `self` stays implicit; `fn var` mutates `self`.
- **Matching**: a conversion to `Source[Int]` checks every operation by name, labels, order, `var`-ness, parameter and result types, exactly as `impl Contract for` does now. Failure names the first mismatched operation. Dispatch, views, and monomorphization are unchanged.
- **Cleanup**: any `fn var T.close() Unit!` makes `T` `Closeable`. `Counted` closes at scope end through its one `close`.
- **Generics**: `fn Box[T].get() T`. Receiver parameters are distinct variables inherited from `type Box[T: Clonable]`, and may add bounds: `fn Box[T: Equal].same(other: T) Bool` exists once and applies only where `T: Equal`. `Source[T]` matches `fn var Pipe[T].next() T?!`, with `T` inferred from the signature. Specialization (`fn Box[Int].f()`) is an error.
- **Interface views, `Equal`/`Hashable`/`Comparable`**: unchanged; `equals`, `hash`, `compare` are ordinary methods matched by shape. A type with a wrong-shaped `close` is simply not `Closeable`; a lint reports a `close` that is not.
- **Removed rule**: "same-named operations from different interfaces need an interface-typed binding" and the overlap analysis (`contracts.md`, "Generic implementations"). Both become unreachable.
- **Hazards**: matching is by shape, so a coincidental `equals`, `hash` or `close` of the right shape conforms. Existing structural `equals`/`hash` fallbacks (`methods()` in `contracts.rs`) apply only when no method exists. One `close` also means a type that is both `Source` and `Sink` cannot release differently per role (the "r"/"w" fixture); one resource, one release.
- **One name, one signature per type**: a type cannot implement `Transform[A, B]` and `Transform[C, D]`, or `Read[Int]` and `Read[String]`. `JsonReading[T]` (`json.ms`) implements one instantiation and is unaffected; other cases get a wrapper type.
- **Visibility**: an opaque type allows no receiver methods outside its file, as `impl` does today. A receiver method on a native type may not duplicate a native method; a method may not share a name with a field.
- Migration: `ms fmt` rewrites `impl T:` and `impl I for T:` bodies to receiver methods; blocks that share a method name (the `Source` plus `Sink` case) are reported as conflicts, not merged, and the nine specialized `sum` impls need hand work.

## Components touched
| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` (`parser.rs`, `ast.rs`, `format.rs`) | `fn [var] Type[Params].name`; drop `impl` | parser and format round trip |
| `crates/ms-check` (`contracts.rs` incl. `holds_resource`, `stmts.rs`, `stdlib.rs`) | duplicate check; shape match replaces `methods_by_contract`; `Closeable` by shape | conformance reject: duplicate method, wrong shape |
| `crates/ms-lower` (`call.rs`, `close.rs`) | `closeable_impl` finds the `close` method | `stream-close-once.ms` rewritten to one `close` |
| `crates/ms-lsp`, `ms-tooling`, `ms-repo-check` | symbols, completion, guide, `impl_adjacency` | existing suites |
| `stdlib/`, `tests/`, `documentation/`, `ms guide` | mechanical rewrite | `make verify-full` |

## Alternatives
- **Do nothing**: the checker already rejects the explicit call, so only the silent no-cleanup and the indent remain. Cheapest, but the two-bodies shape stays legal.
- **Smallest**: keep `impl`; require `impl Closeable` for a type with two `close`s, and error when `record_cleanup` sees several candidates. Fixes the leak, leaves the indent and per-contract duplicates.
- **Runner-up**: receiver methods plus declared conformance (`Counted: Source[Int], Sink[Int]`). Catches typos early but repeats what the signatures say; can be added later as a check-only line.

## Stages
1. Parser and formatter accept receiver methods beside `impl`, with the duplicate rule spanning both forms; `ms fmt` converts. Check: round trip over `stdlib/` and `tests/`.
2. Checker: duplicate rule, shape matching, `Closeable` by shape. Check: conformance corpus.
3. Convert `stdlib/`, tests, docs, guide; remove `impl` and the overlap and local-extension code. Check: `make verify-full`, then Windows and macOS CI on the branch.

## Open questions
- **Specialized receivers.** `stdlib/collections/collections.ms` has nine `impl ListXSum for List[X]` blocks (`Int`, `Float`, `Int8`...). One-per-type forbids them. Recommend a single `fn List[T: Numeric].sum() T` with a stdlib `Numeric` bound (zero and `+`), declared in Manuscript; the alternative is free functions per type.
- **Local extensions** (`tests/e2e/testdata/projects/local_extensions`: modules add `Read` for another module's `Item`). Receiver methods in the declaring module only removes them; other modules write a wrapper type or free function. Recommend removing; it also deletes the per-module `Equal`/`Hashable` map behavior.
- **Accidental `close`.** Any `fn var close() Unit!` auto-closes, which broke the stream drivers in `stdlib/io/io.ms` (closed again by their wrapper); those stay `impl Source`/`Sink`. Document the convention in `closeable.md`.
