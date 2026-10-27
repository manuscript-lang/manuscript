# An explicit close must be the binding's last use

## Summary

- `x.close(); x.read()` checks today and fails at runtime with the Closed error (#1537).
- Proposed: an explicit `close()` on a resource binding is a consuming use. It must be the binding's last use, or `ms check` rejects the later use, the way a move is rejected today.
- No new syntax, no lowering or runtime change. The checker reuses the last-use analysis that moves already use.
- Cost: code that closes a binding and then uses it, or closes it twice, stops checking. About 13 stdlib tests exercise the runtime error on purpose and need another way to hold a second handle.
- Decision: Chinmay asked for option 3 of #1537 (close is a rule of `Closeable`, no new keyword), pending a skeptical review.

## Status

**Parked 2026-10-27** (Chinmay: "lets not worry about consuming close"). A skeptical review found: the check only sees a whole local variable, while the documented idiom closes a field (`task.channel.close()`); a helper or closure evades it; the proposed `.clone()` workaround does not exist for `FileHandle` or `ReadStream`; and rejecting a second `close()` contradicts `closeable.md` and `scopes.md`, which call close idempotent. About 13 existing tests use a binding after `close()` on purpose (fs, log, fetch, net, tasks, processes). Revisit only as a true consuming close with a way to hold a second handle. Proposal, checked against `origin/main` at `5686c341`. Supersedes the recommendation in `check-use-after-close.md` and narrows `consuming-close.md`: this proposal does not change the receiver, so the `SharedGuard` payload hand-back in that proposal stays a separate question.

## Problem

- Verified: `file.close()` followed by `file.read()` passes `ms check`; `FileHandle.close` is documented as safe to call repeatedly, and later operations return `Closed` (`stdlib/fs.ms`).
- A pattern-match check on straight-line code misses `if c: file.close()` and loops. The ownership walker already answers "is this the last use of this binding on every path": `is_last` and `next_use` in `crates/ms-check/src/ownership/walk.rs`, which reject `` `x` is moved here but used again ``.
- Non-goals: closing through fields, list elements, aliases or helper functions; typestate; changing `close` to a consuming receiver; changing runtime close idempotence.

## Design

- Rule: a method call `x.close()` whose receiver is a whole local variable or parameter (not a field path or element) of Resource class is checked like a move of `x`. If `x` has any later use on some path, the call is rejected.
- The binding is not otherwise treated as moved: no `Access::Move` is recorded, so `unclosed_resources` and the implicit scope-end close behave as today, and a conditional `close()` leaves the other path to the implicit close.
- Rejected:
  ```
  let file = try filesystem().open(path, flags: "r", mode: 0)
  file.close()
  let data = file.read()    # error: `file` is closed here but used again at 4:16
  ```
- Rejected: a second `close()` (it is a later use), and `if c: x.close()` followed by any use of `x`.
- Accepted: `x.close()` as the last use; `x.close(); return`; closing in each branch of an `if`; `x.close(); x = reopen()` (the assignment ends the old value's life).
- `with let x = ...:` bindings follow the same rule: an explicit `x.close()` inside the block must be the last use of `x`.
- Messages: `` `x` is closed here but used again at L:C; a closed resource cannot be used, so close it last, or use `x.clone()` for a second handle ``, with its own sub-code.
- Out of scope, still a runtime error: closing a field (`task.channel.close()`), an element, a clone, or a binding captured by a closure.
- Tests that rely on the runtime error obtain a second handle with `.clone()` where the type supports it (verify per type during implementation), or call through a helper function.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check` ownership walk | close-as-last-use rule for whole-variable receivers | reject and accept corpus under `tests/ownership` |
| stdlib and `tests/` that use a binding after `close()` | rewrite to a second handle or a helper | `make conform`, `cargo test --workspace` |
| `documentation/core-language/cleanup/closeable.md` | state the rule | `make docs-check` |
| lowering, runtime, parser, formatter, LSP | unchanged | none |

## Alternatives

- Do nothing: use after close stays a runtime error. Cheapest, and keeps `close` idempotent for every caller.
- Consuming `close` receiver (`consuming-close.md`): same user-visible error, plus lowering and drop-glue work and an unsettled spelling for interfaces. Not needed for this check; remains the route for the `SharedGuard` payload.
- Straight-line pattern check: misses branches and loops; rejected because the walker already has the flow information.
- A new `own def` modifier: general, but a language-surface change for one operation.

## Staging and verification

- Stage 1: the rule and the new corpus cases; run `make verify`, list every existing source it newly rejects, and fix them.
- Go/no-go: the number of newly rejected existing sources, and whether each has a clean rewrite. If real code needs repeated `close()` calls, stop and reconsider.
- Gate: `cargo test --workspace`, `make conform`, `make repo-check`.

## Open questions

- Should a second explicit `close()` be allowed as a special case, since `close` is idempotent? Recommendation: no; the second call is a use of a closed binding, and removing it is the clean fix.
