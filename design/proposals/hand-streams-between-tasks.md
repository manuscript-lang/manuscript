# Hand streams between tasks

## Summary

- Problem: a state-owning task cannot push to its clients, because a pipe carried only copyable values and connection streams may only be touched by their own thread (#4604, #4607).
- Change: a pipe carries any value by move (merged, #4605), and `forward(out)` in `@std/io/forward.ms` makes any thread-bound stream writable from other threads.
- Decision requested: approve `forward` as the general bridge, and keep connection handles on one thread.

## Status

Proposal; 2026-11-19. Owner direction: connection objects are not safe across threads, so keeping them on one thread is a sound choice. Merged part: pipe bound removed. This PR: `forward`.

## Problem

A chat room has one owner task and one handler per client. The owner must write to each client's websocket.

```manuscript
var room = pipe[Command](capacity: 64)    // Command.Join(out: WriteStream[WebSocketMessage])
```

- Before #4605 `pipe[Join]` failed with `Join does not satisfy Clonable`.
- After it, the owner's write to the websocket output faults: the handle is bound to the handler's thread (`ms_std_net::bound::Bound`), so the owner promise ends and nothing is delivered. Verified on the chat server.
- Workarounds seen: log-file polling, UDP, a second TCP connection per client.

## Design

```manuscript
// In the handler, on the connection's thread:
var cmds = room.writer()
cmds.write(Command.Join(forward(output)))?
```

- `forward[T](move out: WriteStream[T], capacity: Int = 16) WriteStream[T]` makes a pipe, starts a `Placement.Here` task on the calling thread that copies the pipe to `out`, and returns the pipe's writer. The writer is plain pipe data, so any thread may use it.
- The returned stream owns the task. `close` closes the pipe writer and waits for the copy to flush `out`.
- Back pressure is the pipe's: a slow client slows only writes to its own writer, once its queue passes `capacity`.
- The owner drops a member when a write fails (the handler left and the pipe's reader is gone), so no leave message is needed.
- No Rust change, no new syntax or type. The connection stays on one thread.
- Not solved here: a promise body cannot move a captured stream into a by-move step such as `lines` (#4606). `forward` avoids it with a helper function that takes the streams as `var` parameters.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/io/io.ms` | no `Clonable` bound on `Pipe` (merged) | `e2e/stdlib/pipe.ms` |
| `stdlib/io/forward.ms` | `forward` | `e2e/stdlib/chat-room.ms`: two websocket clients, owner pushes to both |
| docs, agent skill, wiki | pipes carry streams; use `forward` for connection ends | `make repo-check` |
| `crates/ms-std-net` | unchanged | |

## Alternatives

- Do nothing: the owner cannot push; apps poll or open a second socket per client.
- Make connection handles `Arc` and atomic: about 240 `Rc` uses, and a socket shared by threads needs a close and busy handshake. Rejected by the owner and by `design/proposals/thread-affinity.md`.
- Post the write to the handle's home thread inside the runtime: the same bridge hidden in Rust, with its own queue and back pressure. `forward` does it in Manuscript with the pipe that already exists.
- A built-in broadcast primitive: more API, and the owner's member list is the state it should own.

## Open questions

- Should `forward` also accept a `ReadStream`, so a thread-bound reader can feed another thread? Recommend not until a program needs it.
