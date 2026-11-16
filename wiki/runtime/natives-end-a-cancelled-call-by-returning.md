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

Apply when: adding or changing a native that parks, waits, or polls for cancellation.
Evidence: `crates/ms-rt/src/fault.rs` (`cancel_return`, `take_unwinding`), `crates/ms-repo-check/src/cancel_jumps.rs`.
Verify: `cargo test -p ms-rt --lib guard`; `cargo run -p ms-repo-check`.
