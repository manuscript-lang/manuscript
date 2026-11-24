# Declared move mode

## Summary

- Problem: a body shows whether a function takes ownership of an argument, but an interface operation, a function type, a native and an `extern fn` have none. The checker copies where it cannot see (an impl that keeps a read-only parameter), guesses natives from shape and Rust comments, and faults at runtime for a kept interface-typed parameter.
- Change: `move` on a parameter or receiver says the callee takes ownership. With a body, modes are inferred as today and `move` is optional; without one, a parameter borrows unless marked. A function without a body always returns a new value. One new marker, no call-site marker.
- Decision requested: approve the reversal of the 2026-11-03 decision below.

## Status

Proposal, 2026-11-17, checked at `54265b98`. Direction (Chinmay, 2026-11-17): `move` is the only new marker, borrow is the default, implementations match markers exactly like `var`; chose "owned results without a body" over a `move` marker on results after a second review (that option marked about 360 results, broke `xs.map(fn e: e.name)`, and gave "unmarked" two meanings).
Reverses a recorded decision: "Chinmay declined `.ms` markers and a parameter-level `move` modifier because they pull C ownership complexity into the language (2026-11-03)" (`design/wiki/compiler/native-omissions-are-declared-in-the-standard-declaration.md`).
Stage 1 implemented 2026-11-17: `move` on parameters, receivers and function types; exact matching; interface results and kept parameters rejected instead of copied; `Sink.write`, `Transform.step`, `Transport.write`/`write_bytes` and `HttpExchange.write`/`write_bytes` take `move`, since implementations keep the value.
Stage 2 implemented 2026-11-17: the collection natives (`append`, `insert`, `prepend`, `set`, `replace`, `splice`, `fill`, `Map.add`/`add_default`/`add_default_from`/`remove`/`update`, `Set.add`/`remove`) and the runtime `extern fn`s that keep a value or callback declare `move`, and `StringBuilder`/`BytesBuilder.build` declare `fn move`. Deleted: `RUNTIME_TAKES`/`RUNTIME_KEEPS`, `takes_argument`/`keeps_callbacks`, the stored-shape guess and `copies_elements` in `native_method_modes`, and the `build` name check. Lowering keeps reading the runtime flags as ABI facts; `tests/extern_moves.rs` holds them equal to the declarations. A bound native method value now has the call's modes (`xs.append` is `fn(move T) Void`), so it no longer copies its argument. Not done: `native_borrow.rs` stays, because `List.get`, `Map.get`, `Optional.get` and the views are the primitives a thin body would call; and a named function that keeps a parameter it does not declare `move`, used as a borrowing function value, is still called with a clone, since ending it needs `Optional`/`Result` combinators to take their receiver.
Stage 3 implemented 2026-11-17 (Chinmay chose it): `Optional.map`/`and_then`/`or_else` and `Result.map`/`and_then`/`map_error`/`or_else` are `fn move` and their callbacks `fn(move T)` (`fn(move E)` for the error), so the callback owns the payload and reusing the receiver takes `.clone()`. A function that only reads a parameter stands in where `move` is expected (`lends_where_expected`; the call drops the argument). A named function that keeps a parameter its function type lends is now an error naming the closure with `.clone()` to write; no hidden copy of a function argument remains. The two gaps left then (function values used the borrowed calling convention, so a lambda under `fn(move R)` could not move a resource out, and a method value of a consuming method copied its receiver per call) are closed by [owned arguments through dynamic calls](owned-arguments-through-dynamic-calls.md).

## Problem

Verified in source:

- `Summary::declared` (`crates/ms-check/src/ownership/modes.rs:81`) gives an interface operation only `Borrow` or `Mutate`; dynamic calls use it.
- An impl that keeps such a parameter is called with a copy (`OWNERSHIP.md`, "Interface conversion"); `require_clonable` (`walk/calls.rs:29`) rejects resources and non-`Clonable` types, and an interface-typed parameter copies behind a runtime guard that faults (`OWNERSHIP.md`, "Closures").
- An interface result is always owned: an impl returning its own field is copied at the boundary (`e2e/*/interface-borrowed-result.ms`, "an interface operation returns a copy of a field the method borrows").
- Native modes come from `// ms: takes:`/`keeps:` comments scraped into `RUNTIME_TAKES`/`RUNTIME_KEEPS`, shape guesses in `native_method_modes`, and the name table in `ownership/native_borrow.rs`.
- Interfaces are satisfied by shape (`shape_implements`), so their impls are an open set and cannot be inferred from.

## Design

Rule: your inputs stay yours unless the signature says `move`; a function without a body returns a new value. With a body, both are inferred.

```ms
interface Sink:
    fn add(move item: Item) Void      # proposed: impls take item
    fn name() String                  # result is a new value

fn var Inv.add(move item: Item) Void: # must say move to match
    self.items.append(item)

fn Inv.name() String:
    return self.label.clone()         # a stored field needs .clone()
```

- `move` is allowed on parameters and receivers (`fn move BytesBuilder.build() Bytes`) in any signature. With a body it is optional; written, it is the declared mode and the body is checked against it (a `move` parameter the body only reads is dropped at its end).
- Without a body, an unmarked parameter is a borrow and a result is owned by the caller. There is no result marker.
- Interface implementations match exactly, like `var`: a method satisfies an operation only when its `move` and `var` markers equal the operation's ("`Inv.add` does not match `Sink.add`: `item` is `move` in the interface"). Checked in `shape_implements`, where a value becomes the interface; nothing declares conformance.
- An impl whose result is a part of `self` or an argument is rejected with "returns a part of `self`; `.clone()` it". The hidden result copy and the hidden parameter copy both go; every copy is a written `.clone()`.
- Function types carry `move` and match the same way as interfaces. A lambda takes its modes from the expected type, so `xs.map(fn e: e.name)` is unchanged; under `fn(move T)` it owns its argument.
- Natives and `extern fn` use `move` in their `.ms` declaration. The `// ms:` flags, `RUNTIME_TAKES`, `RUNTIME_KEEPS` and the shape guesses go; `xtask` checks each declaration against its runtime symbol.
- Natives that return a borrow get a thin `.ms` body over a primitive, as `List.first` already does (`collections.ms:22`), so their borrow is inferred. Targets: the entries of `native_borrow.rs` (`get` on `Map`/`List`/`Optional`/`Result`, `view`, `split`, `lines`, `chars`, `keys`, `values`, `slice`). An entry that cannot become a body stays in that table, which is then the one place a bodiless borrow is declared.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` | `move` on parameters and receivers | parser case |
| `crates/ms-check` `modes.rs`, `contracts.rs`, `function_value_modes` | read `move`; exact matching; reject a part returned through an interface | `crates/ms-check/tests/ownership/{accept,reject}`, `tests/interface_modes.rs` (`move` cases beside the `var` ones) |
| `crates/ms-check` `stdlib.rs`, `build.rs`, `native_method_modes`, `native_borrow.rs`; `ms-rt`, `ms-lower/build.rs`, `rtcall.rs`, `xtask` | declarations replace flags and guesses; thin bodies for borrowing natives | symbol check in `xtask`, `make conform`, `make leak-check` |
| `crates/ms-lower` | drop a `move` parameter the body only reads; remove the result copy at interface dispatch | leak check, e2e interface fixtures |
| `stdlib/**/*.ms` | mark consuming parameters; `.clone()` in impls returning a field | e2e stdlib fixtures |
| docs | `references.md`, `function-values-and-closures.md` (fix "invariant" vs one-way `var`), `OWNERSHIP.md`, the 2026-11-03 wiki note | `make repo-check` |

New tests: a kept interface-typed parameter (today's fault), a method satisfying two interfaces, and a leak test on a result returned through an interface.

## Alternatives

- Do nothing: hidden copies on both sides, a runtime fault, natives guessed by shape.
- `move` on results with borrow as the default: one notation everywhere, but about 360 bodiless results marked, `fn(T) move U` breaks `xs.map(fn e: e.name)`, and "unmarked" means "inferred" with a body and "borrow" for matching.
- Infer interface modes across impls: impossible with shape-satisfied, cross-package impls.
- Infer a bodiless result's mode from its type: `List.get` borrows and `List.replace` owns with the same shape.

## Stages

1. Language and checker: `move` on parameters and receivers, exact matching for interfaces and function types, the `.clone()` rule for interface results, lowering drop. Check: ownership fixtures, `tests/interface_modes.rs`, leak check.
2. Standard library: mark natives, thin bodies for borrowing natives, delete flags and guesses in the same PR. Check: `make conform`, symbol check, leak check.

## Open questions

- Direct calls of an impl that now writes `.clone()` copy too (the method cannot know its caller). Recommended: accept; it is visible and a borrowing form stays available as a separate method.
- A non-`Clonable` field (a resource, a `Regex`) cannot be returned through an interface. Recommended: accept until a real case needs a borrowed interface result.
- A method written before an interface existed may lack `move` and so silently not satisfy it; the conversion error names the missing marker. Recommended: accept.
