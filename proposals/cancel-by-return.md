# Cancel by return

## Summary

- Native Rust code that parks calls `msrt_cancelled()` from inside the park. That jump skips every Rust destructor on the frames above it, so each value held across a park needs a hand-registered cleanup (`rt::Parked`, `HeldIo`, `Sending`).
- Make a cancelled park return `Err(Cancelled)` and propagate with `?`, so ordinary destructors run. The FFI boundary calls `msrt_cancelled()` once, after the Rust frames are gone.
- Decision requested: none (no language or user-visible change).

## Status

Proposal, 2026-11-08, checked against `main` at the merge of #3088. Stage 1 (dial path) implemented. A skeptical review found the original shielding claim false and the site list incomplete; both are fixed below.

## Problem

`tools/cancel-sweep.ms` cancels each stdlib test at every park and compares Rust heap blocks with an uncancelled run (#3087). One deterministic leak remains:

```
ms run tools/cancel-sweep.ms -- tests/e2e/testdata/stdlib/http-fault-leak.ms
heap: ... "a fetch cancelled by its timeout frees the request state its frames own" cancelled at park 4 ... 86 Rust heap blocks (uncancelled run: 85)
```

An allocation trace shows the extra blocks are locals of `Client::dial` (the resolved address list and a socket box), which no `Parked` covers. Each earlier leak (#3008, #3046, the 64 KiB read buffer, `HeldIo`) was the same bug fixed for one call site.

## Design

- `wait::wait_fd`, `wait_token`, `sleep`, `blocking` return `Result<Wait, Cancelled>`; `Cancelled` is a unit struct. They stop calling `rt::check_cancel()` and `rt::cancelled()`; a pending cancel returns `Err(Cancelled)` at the park.
- Every native error enum (`NetErr`, `IoErr`, `HttpErr`, `WsErr`, `Fail`, `PumpErr`, TLS and process errors) gains `Cancelled` with `From<Cancelled>`, so `?` carries it through existing signatures.
- `ffi::report` and `ffi::code` are the only places a native result becomes a status. When the error is `Cancelled` they run the shielded cleanup and call `msrt_cancelled()`; the stack is already unwound. `guarded` in `ffi/handler.rs` keeps its status 2 path.
- Shielding: only registered cleanups run shielded (`run_shielded`, `fault.rs`); a `Drop` run while `?` unwinds is not. Rule: a `Drop` that parks takes a `rt::Shield` guard first (the existing `msrt_shield_enter/exit`), and the PR audits each `Drop` that parks (WebSocket close, connection close). Without the shield a parking `Drop` would get `Err(Cancelled)` it cannot return.
- Once the sweep passes without them, delete `rt::Parked`, `ParkedBuf`, `HeldIo` and the `Sending` indirection; helpers go back to plain locals.
- Parks that cannot return a `Result` keep `rt::cancelled()` and their `Parked` cover; the PR lists each: the server's `Token::park` loops (`http/server.rs`), `glue/pool.rs` (`run` returns `Option`), `ms-std-fs` (`poll_cancel`, `admit`), `ms-std-terminal/src/raw.rs`, and any cancel raised inside a generated callback, which still jumps over the Rust frames that called it. Only `guarded` (status 2) is safe there.
- A new `Cancelled` arm in each `Status::code()` match is exhaustive-checked by the compiler; `report` maps it to the jump, never to a user status.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-std-net/src/wait.rs`, `rt.rs` | `Result<Wait, Cancelled>`; drop `Parked` and `HeldIo` last | sweep on `http-fault-leak.ms`, `tasks-cancel-release.ms` |
| `ms-std-net` (`conn`, `net`, `tls`, `dns`, `http/*`) | propagate with `?` (about 48 wait calls and 31 cancel calls in `ms-std-net`, counted with `grep -rn 'wait_fd(\|wait_token(\|check_cancel\|rt::cancelled'`) | `cargo nextest -p ms-std-net`, `make cancel-sweep` |
| `ms-std-net/src/error.rs`, `ffi/mod.rs` | `Cancelled` variants; `report`/`code` jump | sweep only: under `cfg(test)` `msrt_cancelled` already panics, so a unit test cannot show the leak |
| `ms-std-process`, `ms-std-fs`, `ms-std-terminal`, `ms-rt/src/glue/pool.rs` | same pattern where the park can return a `Result`; others keep the jump | sweep on their fixtures |
| `tools/cancel-sweep.ms` | `heap:` hits fail the sweep | `make cancel-sweep` |

## Alternatives

- Do nothing: each new park-holding call site leaks until a soak finds it; the sweep already finds one now.
- Rust panics for cancellation (`panic = "unwind"`): generated code has no unwind tables, release builds use `panic = "abort"`, and a panic crossing generated frames is undefined. It changes the ABI of every crate.
- Keep adding `Parked`: the status quo, one wrapper per leak; the sweep now finds the next one (`Client::dial`) after four earlier ones.
- A scoped cleanup guard around `dial` only: fixes the one leak now, leaves the class open. Stage 1 can ship it first if the full conversion stalls.

## Stages

1. (done for the dial path: `try_wait_fd`, `rt::Cancelled`, `ffi::report`/`code` jump; sweep on `http-fault-leak.ms` no longer shows the +1 block) `wait` returns `Result` and the error enums gain `Cancelled`; the FFI boundary jumps. Gate: `cargo nextest run --workspace`, `make conform`.
2. Convert `ms-std-net` sites and delete the wrappers one by one. Gate: `make cancel-sweep` shows no `heap:` line.
3. Convert process, terminal and pool parks. Gate: sweep on their fixtures.
