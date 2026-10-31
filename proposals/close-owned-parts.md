# Containers and fields close what they own (#1726 stage 2)

## Summary

- A resource held in a record field, an alternative payload, a `List`, `Map` or `Set` is dropped without running its `close()`; only a never-moved binding whose own type has `impl Closeable` is closed at scope end (#1630). Verified on `origin/main` at `8f2c47fe9`: `Holder(R(1))`, `[R(2), R(3)]` and a `Map[String, R]` bound with `let` print nothing at scope end, while `let r = R(1)` prints `closed 1`.
- Now that every owned std handle is a nominal `impl Closeable` type (#1590), ownership is a type-system fact, so a part is owned exactly when its type is `Resource` class.
- Proposed: a binding whose type is `Resource` class through its parts is closed at scope end by a closer generated per type: the type's own `close` first (if it has one), then its owned parts in reverse order. When no part is `Resource` class, the class stays `Copy` or `Move`, no binding is registered, and no code is emitted.
- Not proposed: closing from runtime drop glue (close can suspend), `Shared[T]` last-holder close (next stage), resource temporaries, or overwrite/removal sites (listed under Risks).

## Status

Proposal, 2026-10-28, checked against `origin/main` at `8f2c47fe9`. Direction (Chinmay): "fields and containers close what they own", "if the elements dont have a Closable implemented its a no op", and the close order, including for unordered containers, must be documented. Supersedes stage 2 of `proposals/close-held-resources.md`, whose stage 0 and 1 shipped as nominal handles (`owned-handles.md`). Nothing implemented.

## Problem

- Verified: a record holding a `Resource` field is already `Resource` class (`classify.rs` `nominal` takes the max over fields), so it cannot be copied, but with no `close` of its own the binding is not registered for implicit close (`closable = cleanup.is_some()` in `walk.rs`), so its parts leak silently or, for a leaked binding, the advice names a `.close()` that does not exist.
- Verified: `List`, `Map` and `Set` are always `Move` (`classify.rs` `native`), so a list of resources is not tracked at all.
- Verified: native handles still release the OS resource in Rust `Drop`; what is skipped is the Manuscript `close()` body (flush, wrapper bookkeeping, protocol goodbyes).
- Verified: about a dozen stdlib types hold resources and hand-write `close` to forward to their fields; that forwarding is what this makes automatic.

## Design

- **Class.** `List[T]` is `Resource` when `T` is `Resource`; `Map[K, V]` when `V` is. `Set` is deferred (resource elements are not owned; see the follow-up issue). Otherwise unchanged. Optional, Result and user alternatives already take the max over their payloads.
- **Closer.** For a `Resource`-class binding without a plain `Closeable` implementation, or with one, the lowering synthesizes one function per type, cached by type like `close_thunk`:
  1. the type's own `Closeable.close`, if it has an implementation (idempotent close makes a hand-written forwarding `close` harmless);
  2. record fields in reverse declaration order (Rust drops in declaration order, C++ in reverse; reverse matches C++ and "last acquired, first released");
  3. an alternative: the active case's fields, reverse;
  4. a `List` or `Set`: elements in reverse index (insertion) order; a `Map`: values then keys, entries in reverse insertion order (maps and sets iterate in insertion order, so there is no unspecified order to document);
  5. a part that is not `Resource` class is skipped at generation time.
- **Registration.** The checker records that a `Resource`-class binding with no `close` method is closed by composition: `cleanup` stays `None` and a new fact marks the statement. `unclosed_resources` treats it as closable, so the existing cleanup stack (`bind_closing`, `CleanupPush`) covers faults and cancellation exactly like `with`.
- **Compile-time no-op.** `Resource` class is computed from the concrete element types; `List[Int]` or a record of scalars is `Move`/`Copy`, never registered, and the lowering emits nothing. Verified by comparing the emitted object code of a `bench/perf/` kernel before and after (identical), plus the existing timings.
- **Derived values.** `let name = h.path()` borrows from `h`; a `ref` result cannot outlive the resource it borrows from. A conformance test pins that returning such a borrow from the owning scope is rejected.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check` `classify.rs` | `List`/`Map`/`Set` class from elements | ownership accept/reject corpus |
| `ms-check` `stmts.rs`, `walk.rs` | composite close fact, closable | same |
| `ms-lower` `with.rs` | composite closer generation, `CloseKind` | `tests/e2e/testdata/stdlib/implicit-close-parts.ms` |
| `stdlib/*.ms` | drop hand-written forwarding `close` bodies only where redundant (optional) | `make verify-full` |
| docs | `closeable.md`, `OWNERSHIP.md`: rules and order | docs checks |
| `bench/perf/` | no-op evidence page | rerun, dated section |

## Alternatives

- Do nothing: user types and lists leak their `close()` bodies; hand-written forwarding stays the only way.
- Runtime drop glue: complete, but runs suspending code from Rust drop paths.
- `impl Closeable for List[T]` with a bound on `T` in `.ms`: elegant for lists but does not cover records, which need synthesis anyway.

## Risks

- Newly tracked bindings: any existing `List[Resource]`/record that was silently leaked is now closed or, if moved on unclear paths, newly rejected. Count first by running the corpus.
- Overwrite and removal (`r.f = new`, `xs[i] = v`, `xs.remove`, `m.add` over an existing key) drop the old part without closing. Out of scope here; filed separately as a follow-up.
- Partial moves out of a composite are rejected by the checker, so the reverse walk is sound; alternative payload moves via `match` consume the binding.

## Verification

- Close order test with side-effecting `close` (record fields, list, map, set, nested, alternative, Optional).
- Fault and early-return paths close parts.
- No-op: object-code identity for a non-resource kernel; `bench/perf` kernels within noise.
- Linux, macOS, Windows parity through CI; `make verify-full`.

## Review changes (skeptical review, 2026-10-28)

A reviewer ran the class change over about 4.6k corpus files (one file changes: `shared.ms:92`, `let _held = [guard]`) and found these, all accepted:

- **`derived_from_resource` exempts constructors.** Any call with a resource argument counts as "derived from" it, so `Holder(R(1))` is never registered. Constructors and list/map/set literals take ownership of their arguments, so they are no longer derivation; `group.spawn(..)` and reader wrappers stay.
- **Order with `var def close`.** The own `close` runs first and may write back; the parts are then closed from the post-close value (the slot), like `close_replaced`. Whole-binding reassignment of a composite `var` closes the old composite (same path as `reassigns` in `implicit-close.ms`), and is tested. Field and element overwrite stay out of scope.
- **Idempotence.** Parts may see a second `close` after a forwarding hand-written one; `closeable.md` already requires idempotent close. The new tests use idempotent closes.
- **`.clone()` of a Resource-class type is rejected** (today `R.clone()` is accepted and double-closes); `List[R].clone()` would otherwise join it.
- **Generics.** An unconstrained `T` is `Move`, so a generic local `List[T]` is not registered even when instantiated with a resource; bound `T: Closeable` to opt in. Documented.
- **Conditional moves.** Moved anywhere means never implicitly closed (flow-insensitive, applies to plain resources today); composites inherit it. Filed separately, not widened here.
- **Messages.** The "call `x.close()`" advice for a composite without `close` names closing the parts instead.
- **Evidence.** Object-code identity and the stdlib `close` bodies that become redundant are measured in the PR, not asserted.
