[Wiki](../index.md) › [Compiler and build](index.md)

# Promises borrow their captures and never change them

Verified: the ownership corpus (`crates/ms-check/tests/ownership/*/promise_*.ms`) and `crates/ms-check/tests/promise_fixes.rs`. Decision: Chinmay, 2026-11-02 (concurrency redesign, decisions 5 and rule 5).

- A call of a source function that returns a `Promise` and is given a lambda starts concurrent code. The lambda reads its captures in place and may not change them; the holder of the promise borrows them to the end of its scope. The rule is derived from the declared result type (`ownership/walk/exprs.rs`, `entry_call`), not from the name `promise`, so a user wrapper that returns a `Promise` gets it too.
- Why scope end and not last use: `wait` does not consume the promise, and the work only ends when the promise is dropped, so a change after the last `wait` but before the scope ends would still race a cancelled-but-joining promise.
- A moved promise hands its borrow to its new holder (`all := [p, q]`, `tasks.append(p)`, a lambda's returned promise bound by `ps := xs.map(..)`); `wait_all([p, q])` and other holderless consumers end it. Not carried yet: a promise moved into a record field or an unbound call result (#2481).
- Migration: a call that used to wait and now returns a promise is fixed by `ms check --fix`: `f()?` / `return f()` / `f().member` get `.wait()`, and a bound promise gets it where its result is used. Markdown fences need a fence-aware driver; none exists yet.
- Returned promises own (#2686): a promise-starting call in a `return` (also inside a constructor, list or map built there) is an escaping lambda, so the function moves the parameters and locals it captures (`returned_promises_own_captures`; callers pass `.clone()` to keep a value). Only a promise returned by name keeps the borrow error; a local captured by a returned-by-name promise still ends with the function. Fixtures: `accept/promise_returned_*`, `reject/promise_returned_parameter_used_again.ms`, `accept/returned-promise-owns-captures.ms`.
