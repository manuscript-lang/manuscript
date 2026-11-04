[Wiki](../index.md) › [Runtime](index.md)

# A deferred read runs on the waiter's stack, so its parks must honor the waiter's deadline

Verified: `ReadStream.read()` is a `deferred` promise whose work runs inside the task that waits, so a promise limit (`with(options: PromiseOptions(timeout: d))`) can only stop it through the waits the work performs. `msrt_promise_wait` folds the promise's limit into its deadline and reads `task::defer_deadline`; the socket natives in `ms-std-net` park directly, so before `rt::within_waiter` a read on a silent TCP or UDP socket outlived its timeout forever. Any new native park reachable from a deferred read goes through `within_waiter`.

Apply when: adding a native that parks (`wait_fd`, `sleep`, a token, the blocking pool) under a stream `next`.
Evidence: [net fixture](../../tests/e2e/testdata/stdlib/net.ms), `crates/ms-std-net/src/rt.rs`.
Verify: `socket.input.read().with(options: PromiseOptions(timeout: 100.milliseconds)).wait()` on a silent peer returns an error instead of hanging.
