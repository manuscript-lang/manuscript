# Pipe tickets: send a pipe's writing end to a running task as data

## Summary

- Problem: a caller cannot give an already running task one end of a new pipe. `pipe[T]` needs `T: Clonable` and a stream end is a resource, so `pipe[Reply]` with a `WriteStream` field is rejected. A pool therefore cannot return a `ReadStream` while the connection stays in its worker.
- Change: `Pipe[T].ticket()` returns a plain-data `Ticket[T]` that a task turns into a `WriteStream[T]` with `open()`. The ticket is a copy of a runtime token, so it crosses a pipe, and the runtime lets it be opened once.
- Decision requested: accept a copyable capability token in the stdlib instead of a language change to moves or clones of resources.

## Status

Implemented, 2026-11-15, on `240af686`. Review (Fable): approve with changes, all taken below: reservations live in the pipe cell, reader close releases them, `open` returns an error, lost-ticket and back-pressure cases documented. Chinmay's direction: the worker should send back data, the stream must be a real `ReadStream`, "it should work even with copying", and no move-through-pipe change. Replaces `proposals/streams-carry-handles.md` (a `Sink.write` mode that follows `T`, rejected by Chinmay) and `proposals/pipes-carry-moved-values.md` (a `PipeWriter` type, rejected as unsound).

## Problem

Verified on main: `pipe[Reply]` with `rows: WriteStream[Int]` fails with `Reply does not satisfy Clonable; it is or holds a Closeable resource, which has one owner and closes once, so it cannot be cloned`; the target program is `/mnt/project-files/ms-pg/pool-returns-stream-blocked.ms`. The bound exists because `Sink[T].write` only lends its argument (`stdlib/io/io.ms`, comment on `Pipe`). A resource declaring its own `clone` is still not `Clonable` (checked with a `Handle` that has `close` and `clone`), and a promise closure cannot move a captured resource out (checked on main), so neither a clone nor a lease of the stream works today.

Consequence (ms-pg PR 10): `Pool.each` streams on a pooled connection only as a callback, because the one `ReadStream` a call could return must own a reader the pool owns and cannot get back.

## Design

- `Pipe[T].ticket() Ticket[T]!` reserves one writer in the pipe cell (`reserved` counter under the cell lock, counted in `writers`) and returns `Ticket[T]`: the pipe's generation-tagged id and capacity, so it is plain data and `Clonable`, and crosses a pipe by copy. A stale ticket fails safely on the generation.
- `Ticket[T].open() WriteStream[T]!` claims one reservation (`msrt_pipe_claim`) and returns the writer; a second `open` fails with `EBADF`.
- Closing the pipe's reader releases every reservation, so a ticket nobody opened cannot keep a dead pipe alive; `ticket()` after that fails with `EBADF`.
- A ticket that is lost while the reader stays open keeps the reader waiting, as an unclosed `writer()` does today. A receiver opens and closes every ticket it is sent, including on failure paths.
- A writer on a ticket pipe waits when the pipe holds more than its capacity. A caller that holds the stream while it asks the same worker for another stream can deadlock; read the first stream to the end first.
- No change to `Clonable`, `Sink`, the checker or lowering. The reader stays with the caller: one owner, never copied.

```manuscript
// Proposed; does not check today.
type Ask:
	sql: String
	rows: Ticket[List[Value]]

fn var Pool.stream(sql: String) ReadStream[List[Value]]!:
	var reply = pipe[List[Value]](capacity: 256)
	self.asks.write(Ask(sql.clone(), reply.ticket()?))?
	return ok(reply.reader())
```

The worker does `rows := ask.rows.open()` and passes it to `Conn.run_streaming`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-rt/src/pipe.rs` | `reserved` in the pipe cell; `msrt_pipe_reserve`, `msrt_pipe_claim`; reader close releases | conformance below |
| `stdlib/io/io.ms` | `Ticket[T]`, `Pipe.ticket`, `Ticket.open` | conformance: ticket crosses a pipe; second open is closed; unopened ticket keeps the reader open |
| `crates/ms-lower/rt_symbols.txt` | the two symbols | `make count-check` |
| ms-pg `Pool.stream` | send a ticket in the request | ms-pg tests, bench |

## Alternatives

- Do nothing: `Pool.each` (callback) and `stream()` (own connection).
- Moves through pipes (`Sink.write` mode follows `T`): checker and lowering change; rejected by Chinmay.
- Clonable resources: a resource may not declare `clone` today; the interface-erased `WriteStream` would also need a `Sink.clone`.
- An unchecked integer id as the ticket: forgeable and double-openable; the reserved counter is the guard.
- A global claim table: new cross-thread state; the counter in the cell lock does the same job.

## Tests

`tests/conformance/fixtures/e2e/stdlib/pipe-ticket.ms`: a running task writes through a ticket to a pipe made after it started; a ticket opens once; a ticket keeps the reader waiting until opened and closed; closing the reader releases unopened tickets.
