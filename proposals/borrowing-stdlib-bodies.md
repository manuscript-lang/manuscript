# Stdlib bodies that lend: `List.first`/`last` in Manuscript

## Status

Not pursued (2026-11-12). The skeptical review found the central claim unproven (a body that returns `none` beside `self.get(0)` is the checker's withdrawn "mixed returns" case, `returns.rs:153-160`, not the `return m.get(k)` shape the evidence cites), and that lowering already falls back for boxed optionals (`borrow_shape.rs:77`, `native/list.rs`), so a new `opt.view_at` is not needed. The gain over the merged Rust path is about 0.3 ms (2.3 against 2.6 ms) and `borrowed_shape` still matches `first`/`last` by name, so little Rust would go away. Functions that return scalars have no lending problem and can move to `.ms` directly; see `proposals/retire-ms-rt-hot.md`. Original draft:

Draft. Requested by Chinmay (2026-11-12): move the fast-path functions to Manuscript with no language change; "trading Rust code for more Rust code doesn't make sense"; the direct LLVM emitter is not happening, so there is nothing to wait for. Prerequisite for group A of `proposals/retire-ms-rt-hot.md`.

## Summary

- Problem: the checker and lowering decide which natives lend a borrow of their receiver from a Rust name list (`ms-check/src/ownership/walk/returns.rs` `native_borrow_receiver`; `ms-lower/src/borrow_shape.rs`). A stdlib `.ms` body is not on the list, so `fn List[T].first() T?:` returns an owned value and breaks the contract.
- Change: derive "lends" from the declaration instead of the name, so a stdlib body that returns a borrow of its receiver is treated like the native, then port `first` and `last`.
- Decision requested: the boxed-optional rule (Design, last bullet).

## Evidence

- Measured: `first()`+`last()` over 5M calls on `List[Int]`: 17.8 ms runtime call, 2.6 ms Rust special case, 2.3 ms stdlib body (`if self.is_empty(): return none`, then `self.get(0)`).
- Measured: with the stdlib body, `make conform` fails `e2e/accept/borrowed-container-reads` ("List.first: b3: opt.view cannot borrow a boxed optional") and `ms-check` tests `wrapper_passthrough::preserved_payloads_cannot_be_duplicated` and `unique_receiver_cannot_be_kept_beside_passthrough_result` fail ("`first` returns a reference into `values`").
- Verified: the checker already infers borrow-returning source functions with a fixpoint (`OWNERSHIP.md`, "Borrow-returning functions"; `return m.get(k)` is an `opt.view`).

## Design

- No language, grammar or stdlib API change. The checker's existing borrow-returning inference decides that `first`/`last` return a borrow of the receiver, because every return path is `none` or `self.get(i)`, itself a lend. `native_borrow_receiver` keeps only the natives that stay native (`get`, `view`, `split`, `lines`, `chars`, `keys`, `values`, `slice`) until they are ported the same way, one at a time.
- `ms-lower` reads the same fact for `borrowed_shape` instead of matching `first`/`last` by name; the in-place `Shape::First`/`Last` path becomes the inlined body.
- Boxed optional (a type that contains itself, `type Node: next: Node?`): `opt.view` is rejected today because the optional is a pointer to a heap block and a loaded value carries no address. Proposed: add an `opt.view_at` operation that takes an element address and builds the pointer form, implemented in `ms-clif` and the MIR interpreter, and lift the verifier rule for it. Alternative: copy the payload in lowering when `T` is boxed and `Clonable` (no new op; recursive types that hold a resource still need the call-site fallback to the native).

## Components

`ms-check` (`ownership/walk/returns.rs`, `calls.rs`, `exprs.rs`), `ms-lower` (`borrow_shape.rs`, `native/method.rs`), `ms-mir` (`ir`, `verify/types.rs`, `interp`), `ms-clif` (`lower.rs`), `stdlib/collections/collections.ms`, `ms-rt` (delete `msrt_list_first`/`last`), `rt_symbols.txt`.

## Gates

- `make conform`, `make drift-check`, ownership-counts (`make count-check`), `cargo test --workspace`, clippy.
- The three failures above pass, plus a new fixture for a recursive element type with `first`, `last` and a temporary list.
- No perf regression: `bench/perf/rt-hot-moves` and the engineering suite against `main`.

## Alternatives

- Keep `first`/`last` native with the name list: zero risk, but every fast path stays Rust and the list grows.
- Require `Clonable` on `first`/`last`: changes accepted programs (a list of pipes could no longer call `first`).
- Do nothing.

## Open questions

- Boxed optional: `opt.view_at` (no copy, new op in two backends) or copy in lowering. Recommendation: `opt.view_at`.
