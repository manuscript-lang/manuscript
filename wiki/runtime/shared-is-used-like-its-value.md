[Wiki](../index.md) › [Runtime](index.md)

# Shared is used like its value

Decision (Chinmay, 2026-11-01): `Shared(value)` has no `share`, `get`, `lock` or guard. The handle is used like the value; a `var` handle changes it and a `let` handle only reads it, under the ordinary ownership rules; every call on the value runs one at a time (the call holds the box, another task waits, the same task faults); any payload type works, and the expected type picks handle or value (`names = [9]` replaces the payload, `names = other` rebinds). The lock guard it replaces confused readers about what to use when. Cross-worker sharing is a later stage.

Keep it generic: the checker takes handle behavior from the `Proxy` marker in `@std/core.ms` (`impl Proxy for Shared[T]`), through `proxy_payload` and `Classifier::proxy`, never from the name `Shared`. A value the handle stands for is marked on the expression (`Info.through_shared`, `Info.into_shared`); lowering keys on those facts and on the box layout only. Add a new place where a value fits (an operand, a `for`, a `match`) with `Checker::payload_of`, not a special case.

Failure modes seen: copy-in/copy-out of a `var` argument lost a cancelled call's changes (fixed by the `$mem` instance, which changes the payload in place); holds on the cleanup stack interleaved with the unwind pass's push/discard windows, so holds record their guard depth and `end_abandoned_holds` runs before the cleanups; a park cancelled by a jump skips Rust destructors, so the queue exit is a `with_cleanup` entry; a hold taken before a method's arguments held the box across `slot.append(run())`, so collection changes take no hold.

Decision (Chinmay, 2026-11-01): strict `var`. A method that changes a `Shared` field is `var fn`, with no exception for handles in fields, so `Channel`, `HttpExchange`, log `Transport` and the group handles have `var fn` methods and their entries and handlers are `fn(var ...)` ([var parameters in function types](../../proposals/var-function-parameters.md)). Chinmay's reason: the markers should be able to decide later what may run in parallel. A rebind (`var c = ch`) of a read-only handle still gives a writer; whether to reject it is open there.

Indirect `var` calls: the unwind pass covers a caller slot passed to `call.ind` only when every function made into a closure of that type borrows it, and it stops following a value at `shared.addr` (the box is outside the value). Without both, a task cancelled inside an entry with a `var` channel leaked its end (`tasks-cancel-channel-wait-memory` grew 8 KiB).

Apply when: adding shared state to the stdlib, or touching `Shared`, holds, scope-end cleanup or cancellation cleanup.
Evidence: [proposal](../../proposals/shared-read-and-lock.md), [cancel regression](../../tests/e2e/testdata/accept/shared-cancelled-call-keeps-changes.ms), [reads copy](../../tests/e2e/testdata/accept/shared-reads-copy.ms).
Verify: those fixtures and `e2e/stdlib/shared-timeouts` pass; `grep -rn 'is_std("Shared")' crates/ms-check` finds nothing.
