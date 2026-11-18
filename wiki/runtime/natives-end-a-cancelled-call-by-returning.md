[Wiki](../index.md) › [Runtime](index.md)

# Natives end a cancelled call by returning

Decision: a native that sees a cancel calls `ms_rt::fault::cancel_return()` (also `glue::cancel_return`) and returns a zero result at once. It never calls `msrt_cancelled`. With cancel edges on, `cancel_return` sets the task header's `unwinding` byte and returns; the caller's `br.cancel` then takes the function's cancel exit. Until a module calls `msrt_cancel_edges`, it still jumps, so a converted native is safe in a mixed build ([proposal](../../proposals/cancel-cleanup-by-edge.md)).

Rules:
- Drop what the frame owns before `cancel_return()`: with edges off it jumps and skips destructors.
- A `// ms: leaf` native has no cancel edge after its call, so it must not deliver a cancel. Bigint ops lost their entry `poll_cancel` for this reason.
- Return a harmless status or value: the cancel exit ignores it.
- `msrt_guard_call` and so every task boundary turns a set `unwinding` byte into status 2 (cancelled) and clears it.
- A native that calls generated code (sort comparators, filters) lets the callee run on: a callee that sees `unwinding` returns at its next park. Loops around callbacks keep their `poll_cancel()` checks.
- `make repo-check` (`cancel_jumps`) fails a `msrt_cancelled` call outside `fault.rs` and `start.rs`.

- `unwinding` reads 0 while any cleanup or explicit exit code runs, so a shielded close that parks does not see the flag of the cancel it serves: `msrt_cleanup_unwind_to` clears it for the duration and sets it again before returning, and exits that run code use `msrt_unwinding_pause()` and `msrt_unwinding_resume()`. `deliver_cancel` is idempotent, so a park entered while the flag is set never delivers a second cancel.

- Cancel exits come in two forms. A hybrid exit (`cancel_edges`, after `unwind`) forgets the live owners and runs the registered cleanups above the entry height (`msrt_cleanup_unwind_to`). An explicit exit (`cancel_exit`, built inside `elaborate` for a Raw function whose live owners are scope owners or plainly droppable) ends the same scopes a `return` would, then pops the registrations without running them (`msrt_cleanup_truncate`), because they stay for faults until faults return by flag. The hybrid pass must run after `unwind`: `unwind` discards a window right after its parking call, so a check placed earlier would run the exit with the registration already gone (17 leaking runs instead of 3 on `deque-resource-growth`). An explicit function is never inlined into a hybrid one or the reverse unless the callee cannot park, since each form adds its checks at a different time.

- The cleanup stack lives in the task's header block (`Hdr.cleanups`: buffer pointer, length, capacity at offsets 24, 32, 40). Generated code pushes with a store pair and a length bump and discards with a length store, calling `msrt_cleanup_push` only when the buffer is full and `msrt_cleanup_discard` only when the entry below the handle was retired (a tombstone the runtime prunes). Both backends lower it (`cleanup_push`/`cleanup_discard` in `ms-clif`, `push_entry`/`discard_entries` in `ms-mir-llvm`); a handle is the entry count after the push. On a 3000-task benchmark the runtime calls drop from 2.95M to 0.45M instructions.

Apply when: adding or changing a native that parks, waits, or polls for cancellation.
Evidence: `crates/ms-rt/src/fault.rs` (`cancel_return`, `take_unwinding`), `crates/ms-repo-check/src/cancel_jumps.rs`.
Verify: `cargo test -p ms-rt --lib guard`; `cargo run -p ms-repo-check`.

- What an explicit exit converts (and what keeps a function hybrid): a value taken from a slot a scope owns is put back before the scopes end; one taken from an untagged local slot is dropped like any owner; a scope not yet begun at the park is no reason to refuse, but one already ended has released its values. A derived pointer (`PtrField`, `PtrAdd`) of an owned slot is not an escape by itself, only a parking call or closure that receives it; calls inside a shield window are not cancel points and are skipped.
- Restore contract for `var` parameters: a function with an explicit exit puts back every `var` slot it took from, like its normal exit does (`Cx.restores`). A caller may then pass its slots to a restoring callee and still own them; this is why conversion runs callee first (`callee_first`). A hole (a part moved out of a taken value until `type.fill`) is refilled on the exit: `take` the part slot, `type.fill`, `put` into the var slot. A taken value forwarded whole into a local slot is returned to the var slot (`returns`). If a taken var slot has no such path the function stays hybrid. Putting back into a slot parameter without the contract double-frees (`http-hardening`).
- Still hybrid: a non-Raw `var` forwarder (`HttpExchange.reply`) never goes through `elaborate`, so `restores` is false and its callers stay hybrid; these are the 7 remaining `router.ms` access-log leaks.
