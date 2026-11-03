[Wiki](../index.md) › [Compiler and build](index.md)

# Promises borrow their captures and never change them

Verified: the ownership corpus (`crates/ms-check/tests/ownership/*/promise_*.ms`) and `crates/ms-check/tests/promise_fixes.rs`. Decision: Chinmay, 2026-11-02 (concurrency redesign, decisions 5 and rule 5).

- A call of a source function that returns a `Promise` and is given a lambda starts concurrent code. The lambda reads its captures in place and may not change them; the holder of the promise borrows them to the end of its scope. The rule is derived from the declared result type (`ownership/walk.rs`, `entry_call`), not from the name `promise`, so a user wrapper that returns a `Promise` gets it too.
- Why scope end and not last use: `wait` does not consume the promise, and the work only ends when the promise is dropped, so a change after the last `wait` but before the scope ends would still race a cancelled-but-joining promise.
- Known gaps, recorded in `OWNERSHIP.md` (Promises): a promise moved into a container does not carry its borrow,. A promise started inside a lambda is tracked only when the lambda's own `return` starts it and the call result holds promises (`let ps = xs.map(fn x: promise(...))`).
- Migration: a call that used to wait and now returns a promise is fixed by `ms check --fix`: `try f()` / `return f()` / `f().member` get `.wait()`, and a bound promise gets it where its result is used. Markdown fences need a fence-aware driver; none exists yet.
