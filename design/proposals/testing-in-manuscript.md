# Testing expectations in Manuscript

## Summary

- Problem: every `expect_*`/`assert_*` of `@std/test/test.ms` is lowered by hand in `crates/ms-lower/src/testing.rs` (about 420 lines) because three things cannot be written in `.ms`.
- Change: three small primitives (`caller_site()`, `repr`, `catch_fault`) make the expectations ordinary `.ms` functions. Net about 200 of the 417 lines of `testing.rs` go; `fault_trap`, the error-record helpers and the three arms stay.
- Decision requested: none beyond Chinmay's 2026-11-03 "yes on all three"; the mechanism for `caller_site()` is this proposal's choice.

## Status

Implemented, 2026-11-03, checked at `4095dad8`. Chinmay approved the three primitives: "yes on all three". Item 5 of `architecture/compiler-hacks-audit-2026-11-03.md`.

## Problem

- A failed expectation reports where it was called. `.ms` has no way to see the caller's position, so lowering stamps `details["site"]` (#2406).
- `expect_equal[T: Equal]` prints both values. A `.ms` generic has no text form for an arbitrary `T`; lowering builds one per type with `repr_text`.
- `expect_fault` and `skip` need a fault trap and the fault message; only lowering and the runtime have them.

## Design

**`caller_site()`**: valid only as a parameter default. When a call omits that argument, lowering fills it with the call's `file:line:col` (`call_pos`, `crates/ms-lower/src/call.rs:209`), not with the default's own position as `default_argument` does for other defaults (`call.rs:272-358`). An explicit argument wins. No new syntax. A function with such a default is callable only directly: taking it as a function value or bound method is a diagnostic, because `default_thunk` (`closure.rs:270-344`) has no call site. The stdlib test functions are the only users; `native_args` (`testing.rs:114`) goes away with their arms.

```ms
export fn expect_true(actual: Bool, site: String = caller_site()) Unit!:
    if actual: return ok(unit)
    return error(failure("expected true, got false", site))
```

- A wrapper that forwards its own `site` reports its caller, not itself.
- Using `caller_site()` elsewhere faults at run time with "caller_site() is only valid as a parameter default" (its body); taking a function with such a default as a value is a lowering error. A checker diagnostic is not worth its code for one stdlib function.

**`repr[T](value: T) String`**, exported from `@std/test/test.ms`: the debug text of any value, built by `repr_text` (`text.rs:540`, strings quoted, records and collections spelled out). It borrows `value` and keeps a lowering arm per type, like `expect_equal` today.

**`catch_fault(operation: fn() Unit) String?`**, exported from `@std/test/test.ms`: runs `operation` behind the platform fault trap and returns the fault message, or `none` when it returns normally. The operation is borrowed (as `fault_trap` does today, `testing.rs:308-351`). `skip` is a fault carrying `SKIP_MARKER`, so `catch_fault` re-raises a fault with that marker instead of returning it; cancellation propagates.

**Expectations in `.ms`**: `expect_equal` compares with `==` and reports `repr` of both; `expect_fault` calls `catch_fault`; `skip` is `panic(SKIP_MARKER + reason)` with the marker the runner already reads; `assert_*` forward to `expect_*` with the caller's `site`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check` | `TestHooks` found through `@std/test/test.ms` now that it is a source module | existing fixture conformance |
| `crates/ms-lower` | evaluate `caller_site()` defaults at the call; keep `repr` and `catch_fault` arms; delete the `expect_*` arms | e2e testing fixtures |
| `stdlib/test/test.ms` | bodies in `.ms`; new `repr`, `catch_fault` | existing `tests/e2e/testdata/stdlib/test*.ms` |
| `crates/ms-lsp`, docs | snapshot pins, generated API pages | `make docs-check` |

`fixture.rs` and `runner.rs` are harness entry code (test discovery, cleanup stack) and stay.

## Alternatives

- Do nothing: about 200 lines stay in Rust, outside the language's own checking. No defect motivates the change; Chinmay chose it to move behavior into Manuscript.
- A site stamped by `try` in test blocks: no new primitive, but the column names the `try`, not the call, and helpers outside test blocks lose it.
- `caller_site()` as a hidden parameter on any function: needs a rule for function values and generics; the default form needs only the direct-call restriction above.
- Cost: `site` becomes a public parameter of every expectation (generated docs, LSP snapshots). It also lets helper functions forward their caller's site, which is the point.

## Stages

One PR: a module with any real body is a source module, so the `...` declarations cannot stay beside the `.ms` bodies. `caller_site()` default, the externs, the bodies and the deleted arms land together; `make conform` and the e2e fixtures gate it.

## Open questions

- Should `repr` live in the prelude (the Ruby spike asks for `dbg`)? Recommendation: keep it in `@std/test/test.ms` until that spike decides.
