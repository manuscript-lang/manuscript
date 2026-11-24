# Resources through task channels (D7 for channels and logs)

## Summary

- Problem: a resource such as a `Door` cannot cross a task channel, and a `Logger` was not closed at scope end (#1989).
- Change: the logger transport closes with its last holder (done, #2364). `TaskGroup` uses a concrete `TaskChannel` whose `send` moves its value. No consuming interface mode.
- Left open: automatic close of channel ends by ownership.

## Status

Logger stage merged 2026-11-02 (#2364). Channel stage implemented 2026-11-02 against `origin/main` at `09c89a2b`. Direction (Chinmay): "we're not doing consuming mode ... try the concrete method, why do we [need] an interface for that?"

## Problem

- `TaskGroup[Int, Door, Unit]` failed with "Door does not satisfy Clonable".
- Cause: `Channel` holds a `Transport` interface, and an interface method only lends its parameters (`ownership/modes.rs`). A `send` that stores its value therefore copies it, and the checker rejects converting a type with such a `send` unless `In: Clonable`. A concrete method infers that it keeps its parameter, and the caller moves the value.
- Only task channels can carry resources. Worker and process channels serialize `Data`, so they never needed a move.

## Design

- `TaskChannel[In, Out]` (`stdlib/concurrency/tasks.ms`) is the former `TaskTransport` made public, with concrete `send`, `receive` and `close`. `send(value: In)` moves `value`; the `Clonable` bounds on `TaskGroup`, `Entry` and `spawn` are gone.
- Task entries take `TaskChannel[Out, In]` and `Task.channel` is a `TaskChannel[In, Out]`. `Channel` and `Transport` remain for workers and processes.
- `as_channel(end)` views an end as a `Channel` for `channel_reader` and `channel_writer`. The view copies sent values, so it requires `Clonable` payloads.
- A private `EndGuard` closes the task's own end on every exit, replacing the `Closeable` the old transport carried.
- Ends stay shared handles: `.clone()` shares one, and each holder closes explicitly. A value unread when its end closes is dropped, which closes it.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/concurrency/tasks.ms` | `TaskChannel`, `as_channel`, `EndGuard`, no `Clonable` bounds | `tests/e2e/testdata/stdlib/task-channel-resource.ms`: a `Door` is received and closed once |
| task tests and docs | `Channel[` becomes `TaskChannel[` | existing task-channel fixtures |

## Alternatives

- Do nothing: resources stay confined to a task.
- Consuming interface parameter: rejected by Chinmay.
- Owned `Closeable` ends: a resource cannot be `.clone()`d, and the group keeps a second handle on every end, so ends need a counted handle first.

## Open questions

- Automatic close of an end by ownership (the remaining #1989 wish) needs a counted-close design for ends held by both the group and the task.
