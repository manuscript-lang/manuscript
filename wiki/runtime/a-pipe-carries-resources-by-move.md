[Wiki](../index.md) › [Runtime](index.md)

# A pipe carries resources by move

Decision (#4604): `Pipe[T]` and `pipe[T]` have no `Clonable` bound. A write copies a plain value and moves a resource, because the checker already picks copy or move per `T` at the call. A state owner can therefore receive a record holding the client's `WriteStream` and push to it, so a chat room needs no polling file, UDP or second TCP connection.

Not fixed: a promise closure cannot move a captured stream into a step that takes it by move (`for line in input | lines` in a promise body), because the checker treats a closure as able to run more than once. Do that work inline in the handler, or in a function that receives the stream as a parameter.

Apply when: designing request/reply or broadcast between a handler and a state owner.
Evidence: [pipe.ms](../../tests/conformance/fixtures/e2e/stdlib/pipe.ms) (`a pipe carries a writer by move`), [HTTP server guide](../../documentation/core-language/concurrency/http-server.md).
Verify: `ms test tests/conformance/fixtures/e2e/stdlib/pipe.ms`.
