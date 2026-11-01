# `var` parameters in function types

## Summary

- Under strict `var` for `Shared` (a method that changes a `Shared` field is `var fn`), the interfaces whose implementations keep state in `Shared` get `var fn` methods: `HttpExchange`, `Channel`/`Transport`, the log `Transport`, and the group handles. Their callers receive the value as a parameter of a function type (`fn(HttpExchange, RouteParams)`), and a function type could not take `var`.
- Change: a function type may mark a parameter `var` (`fn(var HttpExchange, RouteParams) Unit!HttpError`). A function or lambda declared with that `var` parameter is a value of that type; a call through it passes the argument with `var`.
- Language change. Decisions (Chinmay, 2026-11-01): strict `var`, with `var` parameters in function types, so that mutation markers can later decide what runs in parallel.

## Status

Built on branch `claude/project-thread-838z66` (not merged); follows [shared-read-and-lock](shared-read-and-lock.md) open question 1. Independent review, 2026-11-01: "do not build as written". Corrections applied below. Open question 1 decided (Chinmay, 2026-11-01): reject the copy. Question 2 is built as recommended, with Chinmay's answer pending.

## Problem

- `fn apply(f: fn(var Int) Unit) Int` failed with `parse: expected a name, found 'var'`, and a function with a `var` parameter could not be a value (`exprs.rs`, removed), open since #1191.
- The workaround the diagnostic suggested is a rebind: take the end by value and copy it (`var c = ch`), 37 sites at `HEAD`. Under strict `var` this is the only way a handler or entry changes state, and it works only because copying a read-only handle gives a writer. The markers then say nothing: a `let` handle is one line from a writer.
- Measured at `HEAD` (`git grep -o`, `stdlib tests documentation bench`): 85 `: HttpExchange`, 64 `fn(HttpExchange`, 69 `: Channel[`. Logger methods become `var fn` too, because log `Transport.write` calls `WriteStream.write`, which is `var fn`.

## Design

```
fn bump(var n: Int) Unit:
    n += 1

fn twice(f: fn(var Int) Unit, var n: Int) Unit:
    f(var n)
    f(var n)

let add_two = fn(var n: Int) Unit: n += 2
let route: fn(var HttpExchange, RouteParams) Unit!HttpError = fn var exchange, params: ok(unit)
```

- **Identity.** `var` is part of the function type: `fn(var Int) Unit` and `fn(Int) Unit` differ, and compatibility stays invariant. A mismatch says to mark the same parameters in both.
- **Lambdas.** `fn(var n: Int) ...` and `fn var n: ...`. A lambda does not take `var` from the expected type, so each change is visible where it happens.
- **Calls through a value.** As a direct call: a `var` parameter needs a `var` argument that is a variable or a field path; `var` on a plain parameter is rejected; `var` arguments may not overlap each other or the called value (`m.step(var m)` is rejected, since the callee could replace `m.step` while it runs).
- **Lowering.** A `var` parameter passes a slot address, as for direct calls. A named function used as a value calls its in-memory instance, and a lambda's `var` parameter is the caller's slot, so the value stays in the caller's slot for the whole call. A function that declares `var` but only reads gets a thunk that loads from the slot. The HTTP server's handler thunk puts the exchange in a slot when the handler takes it `var`, so the native ABI is unchanged.
- **Cancellation.** The unwind pass registers a caller slot passed to `call.ind` when every function made into a closure of that type only borrows the slot, as it already does for interface methods. It also follows the value through local slots and stops at a `Shared` box, whose contents are outside the value. `tasks-cancel-channel-wait-memory` shows growth 0 and no live blocks.
- **Method values** with `var` parameters other than the receiver stay rejected ("method value with changed parameters").

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-syntax` parser | `var` in `fn(...)` types and short lambdas | parse fixtures |
| `ms-check` types, calls, ownership | `Param.mutable` in identity, key, display, unify; call modes; callee overlap | reject snippets |
| `ms-lower`, `ms-mir` unwind | slot ABI for `call.ind`, thunks, lambdas, HTTP handlers; closures in slot safety | run fixtures, leak check |
| stdlib | `var fn` on the interfaces and handles above; `fn(var ...)` handler and entry types | `make conform`, `make e2e` |
| docs, wiki | concurrency guides; function values | doc examples |

## Alternatives

- **Do nothing (rebind).** Keep `fn(T)` types and copy inside the body. No language change, but `let` is not read-only and markers cannot drive parallelism. Rejected for the stated goal.
- **Field exception.** A type's methods change its `Shared` fields from `fn`. Rejected by Chinmay.
- **Let `fn(T)` fit `fn(var T)`.** Fewer marks on read-only handlers, but needs adapter thunks and hides which handlers change the exchange. Later, if the churn shows it is worth it.

## Decisions

1. Copying a handle on shared state (`var e = ex`, `ex.clone()`, a record built from `self.field`) out of a `let` or a plain parameter is an error, so `let` means read-only. The types are those `Classifier::shares_state` finds: a `Proxy`, an interface with a `var fn`, or a type holding one. A `let` that owns its value hands it on at its last use. Since one-owner references (#2199) records and interface values move instead of copying, so in practice the rule covers `Shared` handles and `.clone()`. Decided by Chinmay: "Reject the copy, build fn(var T)".
2. A stored closure may pass a handle it captured from a `var` as `var`; the change reaches the shared state, and the closure still counts as reading its capture. Changing a capture taken from a `let` is an error. Built as recommended; Chinmay's answer is pending.
