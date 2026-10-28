# Owned handles are nominal types (#1590)

## Summary

- Interface handles (`FileHandle`, `Connection`, `HttpClient`, ...) are never classed `Resource`, so an opened file that is never closed passes `ms check` and is not closed at scope end (#1590). Classing every interface with `close()` as a resource closed process `stdout` (#1691, reverted in #1731).
- The close-on-drop review traced five close regressions to one cause: ownership is inferred from "has a `close()`". Two skeptical reviews rejected the alternatives (an interface-shape rule with an accessor guard; `impl Closeable for Interface`, which has no body and no precedent).
- Direction (Chinmay): make the owned handles nominal std types with `impl Closeable`, like `Process`, `Fetcher` and `SseReader`. Interfaces stay abstract and are never owned; process-owned accessors (`stdout()`, `stdin()`, `network()`) keep returning interfaces. Ownership is then the existing rule, "a type with `impl Closeable`", with no new language construct and no std name in the checker.
- Stage 1 is `FileHandle` end to end; the rest (`Directory`, `TemporaryDirectory`, `FileWatcher`, `Connection`, `Listener`, ...) repeat it one PR at a time.

## Status

Proposal, 2026-10-27, against `origin/main` after #1737. Direction quoted: "yeah lets do a nominal type", "no lets do it properly, do it via nominal type", "we need to move away from treating stdlib as special case compiler implementation".

## Problem

- Verified: `Classifier` puts only types with `impl Closeable` in the resource set; interfaces are `Move`, while `with` accepts any interface with `close() -> Unit` (`contracts.rs` `closeable`). `FileHandle` is an interface implemented by a runtime handle, so `let f = try filesystem().open(..)` is unchecked (#1590).
- Verified: `impl Closeable for <interface>` is rejected by design ("implementation receiver must be nominal source data"), and there is no interface-to-interface conversion, so a non-closing view of `WriteStream` cannot exist.
- Verified: a nominal wrapper over an `extern type` with `extern def` methods works today (prototype: `NativeFile` plus `msstd_fs_open` and `msstd_fs_file_sync` as `extern def`, opened and synced a file with no compiler change). `processes.ms` already does this for `Process`.
- Verified: the only thing that blocks it is the constructors. `FileSystem.open`, `open_flags` and `temporary` are interface methods whose forwarders (`natiface.rs`, `rtcall.rs` `status_result`) wrap the runtime handle into an interface value; they must build the nominal record instead.

## Design

- **Types.** `export extern type NativeFile`; `export type FileHandle` wrapping it; `impl FileHandle:` with the 24 operations as `.ms` methods over `extern def`s; `impl Closeable for FileHandle:` with `close`. Fields stay as private as the language allows.
- **Constructors.** In `status_result`, when the payload of a native `Result[T, E]` is a record whose only field is the handle type, the runtime still writes a handle and the lowering builds the record (`rec_new`), the way it wraps an interface today. The rule is by shape, not by name.
- **Table removal.** The 24 `("fs", "FileHandle", ..)` rows leave `natiface.rs`. The `InfoOut` stat and the handle-returning `reader`/`writer` are already handled by signature in `rtcall.rs`, so they need no special case.
- **Ownership.** `FileHandle` is `Resource` through the existing `impl Closeable`, so a never-moved binding closes at scope end and an unclosed one is rejected.
- **`Shared[FileHandle]`.** Already `Resource` by the existing `Shared` rule. Tests that share a handle across tasks and close it from any alias are rewritten to own it in one place (the sanctioned way to share a resource), or the sharing rule is revisited separately (open question for the reviewers).
- **Mocks.** A user type can no longer be a `FileHandle`. Code that needs a substitutable file declares its own interface.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/fs.ms` | `NativeFile`, `FileHandle` record, `impl`s, externs | e2e fs tests, `leak.ms` from #1590 |
| `ms-lower` `rtcall.rs` | record wrap in `status_result` | native-record e2e |
| `ms-lower` `natiface.rs` | remove `FileHandle` rows and vtable use | `make conform` |
| `ms-check` | none expected | ownership accept/reject corpus |
| tests, docs | `Shared[FileHandle]`, `fs` docs, `OWNERSHIP.md`, `closeable.md` | docs checks |

## Alternatives

- **Interface supertrait** (`interface FileHandle: Closeable`): general, about a tenth of the work, adds interface-extends grammar. Rejected in favour of the nominal types.
- **`owned interface` modifier**, **std-only list**, **inferring from `close()`**: rejected in review.
- **Do nothing**: #1590 stays a documented gap.

## Risks to challenge

- The 84 `.open(`/`.temporary(` call sites and any code that stores a `FileHandle` in a record, `Shared`, or a collection.
- `reader()`/`writer()` views alias the file; closing a view closes the file (idempotent close makes it benign).
- Newly flagged stdlib holders (`Tap` in router.ms holds an `HttpExchange`; not in this stage).
