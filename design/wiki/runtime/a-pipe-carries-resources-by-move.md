[Wiki](../index.md) › [Runtime](index.md)

# A pipe carries resources by move

Decision (#4604): `Pipe[T]` and `pipe[T]` have no `Clonable` bound. A write copies a plain value and moves a resource, because the checker already picks copy or move per `T` at the call. A state owner can therefore receive a record holding the client's `WriteStream` and push to it, so a chat room needs no polling file, UDP or second TCP connection.

Connection, websocket and other network handles stay on one thread (owner decision, 2026-11-19: they are not safe for several threads, so that is a sound choice). `forward(out)` in `@std/io/forward.ms` is the general bridge: a pipe plus a `Placement.Here` task on the handler's thread, so a state owner on another thread can write to any such stream.

Not fixed: a promise closure cannot move a captured stream into a step that takes it by move (`for line in input | lines` in a promise body), because the checker treats a closure as able to run more than once. Do that work inline in the handler, or in a function that receives the stream as a parameter.

Apply when: designing request/reply or broadcast between a handler and a state owner.
Evidence: [pipe.ms](../../../tests/lang/stdlib/pipe.ms) (`a pipe carries a writer by move`), [HTTP server guide](../../../documentation/core-language/concurrency/http-server.md).
Verify: `ms test tests/lang/stdlib/pipe.ms`.
