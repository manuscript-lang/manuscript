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

Apply when: adding or changing a native that parks, waits, or polls for cancellation.
Evidence: `crates/ms-rt/src/fault.rs` (`cancel_return`, `take_unwinding`), `crates/ms-repo-check/src/cancel_jumps.rs`.
Verify: `cargo test -p ms-rt --lib guard`; `cargo run -p ms-repo-check`.
