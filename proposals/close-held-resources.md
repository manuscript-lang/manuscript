# Close what a value owns: fields and list elements

## Summary

- A resource held in a record field, a list element, a temporary or a `Shared` payload is dropped without running its Manuscript `close()` (#1726). Only a never-moved `let`/`var` binding is closed at scope end (#1630).
- Direction (Chinmay): owning containers close what they own, as in Rust and C++: a list closes its elements, a record its fields.
- Proposed, in order: (0) standard streams stop being caller-owned resources; (1) close two silent holes in today's check; (2) a binding of a record or list that owns resources closes them at scope end through a synthesized closer.
- Not proposed: a rule rejecting resource temporaries (it would reject `stdout().write(..)`, about 1,100 uses), or `close()` from runtime drop glue.
- Decision requested: approve the order, and the standard-stream choice in Stage 0.

## Status

Proposal, 2026-10-27, checked against `origin/main` at `d7a0d5ce`-era sources (after #1731). Direction quoted: "list should get close as it's owning, fields should too ideally, how is it handled in rust and cpp". A skeptical review of the earlier draft found the temporary rule unshippable and the evidence thin; this draft applies its required changes. Nothing implemented.

## Problem

- Verified (`ms run`, repro in #1726): `let h = open_handle("x")` prints `closed x` at scope end; `open_handle("t").id()`, `Holder(open_handle("f"))` and `[open_handle("e")]` print nothing, for both interface handles and `impl Closeable` types.
- Verified: native handles still release the OS resource in Rust `Drop` (`crates/ms-std-fs/src/stream.rs`). What is skipped is Manuscript `close()` code (loggers, stream wrappers).
- Verified: `let h2 = mk(5)` where `Holder` holds a resource but has no `close` reports ``call `h2.close()` `` advice that cannot be followed; `let ho = Holder(R(3))` is silently never closed because `derived_from_resource` (`crates/ms-check/src/ownership/walk.rs`) exempts any call with a resource argument.
- Verified: `List[T]` is always `Move` class (`classify.rs` `native`), so a list of resources is never a resource.
- Verified: about 13 stdlib types hold a resource in a field and most write their own `close`; hand-written `impl Closeable` is the norm (10 in stdlib, 80 in tests, docs and bench).
- Regression found while reviewing: classifying interface handles as resources closed process `stdout` at scope end (#1691, reverted in #1731), because `stdout()`, `stderr()`, `stdin()` and `network()` return interfaces with `close() -> Unit`.
- Non-goals: consuming close (parked, #1537), `Shared[T]` last-holder close, suspending `close()` from runtime drop glue.

## How Rust and C++ do it

- Rust: `Drop::drop` runs, then fields drop in declaration order; a `Vec` drops its elements in order; a temporary drops at the end of its statement; moved values are skipped. `Stdout` is a handle that never closes fd 1. `drop` cannot suspend or return an error.
- C++: the destructor body runs, then members in reverse order; `vector` destroys elements in reverse; temporaries die at the end of the full expression; destructors do not throw.
- Manuscript differs in one way: `close()` may suspend and may fault. Runtime drop ops (`TypeDesc.drop`, ABI.md) are Rust and cannot park a task safely, so the close runs at statically known points through the cleanup stack (`CleanupPush`, `bind_closing` in `crates/ms-lower/src/stmt.rs`), the same path `with` uses.

## Design

- **Stage 0: process streams are not caller-owned.** `stdout()`, `stderr()` and `stdin()` hand out a handle whose `close()` flushes but never closes the descriptor, like Rust's `Stdout`. Then classifying interface handles as resources no longer closes them. Today an explicit `stdout().close()` closes fd 1 (verified); this changes that. `network()` is checked in the same stage. Reopens the #1590 fix (opened files that leak) behind this change.
- **Stage 1: close two holes, no new close.** Track `Holder(R(..))` (drop the constructor-argument exemption in `derived_from_resource`), and when a resource type has no `close`, say ``give `Holder` a close that closes `inner` `` instead of advising `.close()`.
- **Stage 2: owned parts close with their owner.** A record, alternative or `List` whose fields or elements are resource class is itself resource class (generic `List[T]` with unconstrained `T` stays `Move`; resource-ness comes from the concrete element type at the binding). A binding of such a type is closed at scope end by a generated closer: the type's own `Closeable.close` first, if any, then each resource field in reverse declaration order, then list elements in reverse index order. Resources cannot be cloned and a field cannot be moved out of a record (`cannot move t.a out of t`), so a part never leaves its owner and the reverse-order walk is sound.
- **Shared handles.** Records that hold a shared-end handle (channels, loggers) are resources only if the handle itself is resource class; interface handles that are shared by `.clone()` keep their current class until Stage 0 settles who owns them.
- **Temporaries.** Unchanged. A resource temporary used as a receiver (`open("t").id()`) keeps relying on Rust `Drop` for native handles. Revisit after Stage 2 with a rule that exempts process-owned accessors.
- Examples to be checked against stubs before approval:
  ```
  let h = Holder(open_handle("f"))    # Stage 2: closes `inner` at scope end; Stage 1: `h` is tracked
  let hs = [open_handle("e")]         # Stage 2: closes each element, last first
  ```

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/io.ms`, `crates/ms-std-fs` | standard streams: `close` flushes only | e2e: close then write still works |
| `crates/ms-check` classify, walk | constructor hole, diagnostic, composite class | ownership accept/reject corpus |
| `crates/ms-lower` `stmt.rs`, `with.rs` | generated closer for composites | `tests/e2e/testdata/stdlib/implicit-close*.ms` |
| `crates/ms-clif`, `ms-rt` drop glue | unchanged | none |
| `stdlib/*.ms`, tests | fix newly flagged holders | `make conform`, `cargo test --workspace` |
| docs (`closeable.md`, `OWNERSHIP.md`) | state the rules | docs checks |

## Alternatives

- Do nothing: cheapest, and most stdlib holders already write `close`. The gap stays for user types and lists.
- Runtime close-on-drop from glue: complete, but runs suspending code from Rust drop paths and during unwinding.
- Reject resource temporaries: unshippable (about 1,100 `stdout()/stderr()/stdin()` uses, 117 `network()` uses).
- Stages 0 and 1 only: removes the regression class and the silent holes, adds no closes.

## Staging and verification

- Stage 0, 1 and 2 land as separate PRs, each green on Linux, macOS and Windows with no test gated. Stage 2 requires a count first: composite holders that lack a `close` and the sites that would turn into implicit closes or errors.
- Go/no-go for Stage 2: that count, and no regression on `bench/perf/` binding-heavy kernels.

## Open questions

- Standard-stream `close`: flush only (recommended), or keep closing the descriptor and exempt process accessors in the classifier?
- Should `Shared[Resource]` close at the last holder? Deferred; needs refcount-time close.
