# Use after close at check time

## Summary

- `x.close(); x.use()` is caught only at runtime by the closed-state error (#1537).
- Proposed: do not ship a straight-line check now; pursue consuming `close` (`proposals/consuming-close.md`), which makes the error a move error through the existing ownership checker.
- Cost of waiting: use after close stays a runtime error.
- Decision requested: approve waiting for consuming close, or approve a straight-line check with a stdlib opt-out.

## Status

Proposal, 2026-10-27, checked against `origin/main` at `5f28e5d0`. #1526 (unclosed resources) deliberately left this out: only the straight-line case is catchable without typestate, and about 13 stdlib tests exercise the runtime closed-state error on purpose.

## Problem

- Verified: the ownership walker (`crates/ms-check/src/ownership/walk.rs`) tracks a `Resource` binding only for "never closed" (`unclosed_resources`); `close()` does not change the binding's state.
- A straight-line check (a call on a binding after `.close()` in the same block, no branch or loop between) would miss `if c: x.close()` and any close through an alias or a helper, so it gives a false sense of coverage.
- Close is idempotent by contract (`FileHandle.close`: "safe to call repeatedly; later operations return Closed"), so later use is a defined error value, not undefined behavior.
- Non-goals: typestate, and changing close idempotence.

## Design

- Chosen: no new rule now. When `consuming-close.md` lands, `close` takes its receiver by move, and use after close becomes the existing "used after move" diagnostic, with branches and loops handled by the move checker already.
- If the owner wants a check sooner: reject a method call on a binding after an unconditional `x.close()` in the same block, and let tests that exercise the closed-state error opt out with a scoped allowance and a reason, as AGENTS.md describes for flat-match tests.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check` ownership | none until consuming close; otherwise a straight-line rule | reject corpus case |
| stdlib tests of the closed-state error | opt-out only in the straight-line variant | existing tests |

## Alternatives

- Do nothing: matches the chosen option until consuming close lands.
- Straight-line check: cheap, but partial, and it needs an opt-out in about 13 tests.
- Typestate: precise, but a new type-system feature; larger than the defect justifies.

## Staging and verification

- Chosen option: none. Straight-line variant: land the rule with the opt-outs in one PR; `make verify-full` is the gate.

## Open questions

- Wait for consuming close (recommended), or ship the partial check now?
