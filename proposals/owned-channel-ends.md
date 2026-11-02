# Owned channel ends and logger close (D7 for channels and logs)

## Summary

- Problem: a resource such as a `Door` cannot cross a channel, and a `Logger` was not closed at scope end (#1989).
- Change: stage 1 (implemented) closes a logger's transport when the last logger holding it drops. Stages 2 and 3 move values through channels and make ends owned.
- Decision requested for stage 2: how an interface method declares a consuming parameter.

## Status

Proposal; stage 1 implemented 2026-11-02 against `origin/main` at `fa9c09eb`. Part of D7 in `proposals/solid-value-semantics.md`. Independent review (2026-11-02) found three defects in the first draft; this version applies them.

## Problem

- `TaskGroup[Int, Door, Unit]` fails with "Door does not satisfy Clonable": the bounds on `In` and `Out` (`stdlib/tasks.ms`) exclude resources.
- `Transport.send(value: In)` (`stdlib/io/channels.ms`) only lends, so storing the value copies it, and a copied resource closes twice.
- Interface dispatch knows only `Borrow` and `Mutate` parameter modes (`ownership/modes.rs`), so an interface method cannot consume today.
- `Logger` documented that its owning scope closes it, but dropped it without closing the transport.

## Design

- `Shared[T]` closes its payload on last drop only when `T` is the `Closeable` interface (`ms-lower/src/close.rs`, `register_shared_close`). A bare `Transport` is not `Closeable`, and there is no interface inheritance.
- Stage 1: `Logger.transport` is `Shared[OwnedTransport]`, where `OwnedTransport` is a record holding the `Transport` with `impl Closeable`. Children share it; the last drop closes the transport. Explicit `close()` still closes it for all holders, and the later drop-close is a no-op because `Transport.close` is idempotent. No language change.
- Stage 2: `send` consumes its value and the `Clonable` bounds on `TaskGroup`, `spawn`, `Entry` and `run` go. Needs a consuming interface parameter: a language change. Recommendation: let the interface declare the mode with the existing call-mode vocabulary (`retained`), not new syntax.
- Stage 3: `Channel` ends become owned and `Channel.clone()` goes. Fan-out cannot use `Shared[Channel]` with `lock`: a receiver parked under the lock would block every sender. Fan-out needs a design of its own (separate ends per sender), and the group-close lease must keep closing retained ends (`tests/e2e/testdata/stdlib/task-channel-lifetime.ms`).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/log.ms` | `OwnedTransport`, `Shared[OwnedTransport]` (stage 1) | `tests/e2e/testdata/stdlib/log.ms`: scope closes, dropped child does not |
| `ms-check` ownership modes, `stdlib/io/channels.ms`, `stdlib/tasks.ms` | consuming `send`, no `Clonable` bounds (stage 2) | accept `Door` through a task channel; reject use after send |
| channels, tasks, workers | owned ends (stage 3) | task-channel-lifetime and full CI matrix |

## Alternatives

- Do nothing: resources stay confined to a task and loggers close by hand.
- Make `Transport` itself `Closeable`: needs interface inheritance, a larger language change than the wrapper.
- `Shared[Channel]` for fan-out: rejected, deadlocks as above.

## Open questions

- Consuming interface parameter spelling (stage 2). Recommendation: existing call-mode vocabulary.
- `Logger.close()` keeps closing for all holders; accept, since dropping now covers the owner-scope case.
