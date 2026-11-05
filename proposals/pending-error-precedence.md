# Preserve a pending domain error during close

## Summary
- A failing scope close replaces an already-selected body error, violating the existing close precedence contract (#2607).
- Account for implicit close outcomes in ownership inference and select pending errors before considering close-error propagation.
- Repair existing Result ownership machinery; add no syntax, runtime state, copies of resources or verifier exceptions.

## Status
- Implemented under validation,2026-11-05; baseline5ade79d71081246b35f9235595915b825336d6c0.
- User direction: "ensure a proper fix, not a hacky one"; the precedence rule is already documented.
- Independent structural review supports the bounded model; exact implementation review remains required.

## Problem
- Contract: documentation/core-language/cleanup/closeable.md keeps an error already being returned and closes every remaining resource.
- Verified source: propagate_close_error tests error compatibility before pending outcome and drops pending_return whenever a close fails.
- Verified source: pending_return stores Value without ownership, allowing a borrowed pending result to be dropped.
- Verified source: mixed_returns uses an explicit owned-return source position as semantic proof that an owned path exists.
- A function with only borrowed source returns can nevertheless return an owned Error from an earlier implicit close.
- Whole forwarded borrowing Results also record owned cases without necessarily recording that diagnostic position.
- consumed_param_resources currently adds cleanup facts after mixed_returns, excluding another hidden close outcome.
- Baseline reproducer: the new owned precedence fixture returns ECLOSE instead of EBODY/ETRY; borrowed-return control fails unchanged MIR ownership verification.
- Baseline repros and original rejected guard-only candidate remain retained privately; no held validation is needed.

## Design
- The pending domain error is selected before close Error compatibility, replacement or disposal of the pending result.
- If pending_return is a standard Result.error, drop only the close result and continue the remaining ordinary cleanup.
- If pending_return is Result.ok or absent, preserve existing first-close-error propagation; incompatible result error types still fault.
- Inspect the outer Result case only; an error nested inside an ok payload does not suppress cleanup Error.
- Preserve normalized pending-return ownership alongside its Value; replacement drops only a value the function owns.
- Preserve the exact existing owned error value and every message/kind/details field; do not reconstruct an Error from text.
- Finalize local and consumed-parameter implicit cleanup facts before computing mixed return ownership.
- A compatible implicit close contributes an owned Result.error outcome using canonical Result/Error identities.
- A generic error type that can instantiate Error must conservatively include that outcome; concrete incompatible error types do not.
- Determine owned-path presence from actual owned-case facts as well as explicit return positions; positions remain diagnostic metadata.
- Existing disjoint-case borrowing retains borrowed ok with owned cleanup error; use the existing borrowing alternative representation.
- Overlapping borrowed/owned Error cases use only existing legal Result-boundary normalization; never clone a resource or weaken checking.
- Whole Result forwarding must preserve or legally normalize its case mask, including callers whose sources are temporary.
- Keep first close Error when no domain error was pending; later close errors are dropped after their resources close.
- Explicitly handled close errors, nonfallible-function faults, holder/temporary fault policy and cancellation/fault cleanup remain unchanged.
- No new representation, runtime ABI, global state, generic get/iterator changes or ScopeDiscard analysis is proposed.
- If the repair requires held branch-sensitive ScopeDiscard proof or forbidden copying, stop and report rather than weakening the contract.

## Components touched
| Component | Change | Test |
| --- | --- | --- |
| crates/ms-check/src/ownership/walk.rs | Include implicit/forwarded owned outcomes before existing case normalization | Borrowed ok/error, forwarded Result, generic and consumed-parameter cases |
| crates/ms-lower/src/func.rs | Retain normalized pending result ownership | Borrowed caller Error remains valid; owned pending return disposed once only on replacement |
| crates/ms-lower/src/close.rs | Preserve pending error before propagation compatibility | Owned/borrowed/custom errors, success, first-close-error, nested scopes and all-close traces |
| tests/e2e/testdata/accept | Permanent behavior and ownership regressions | Debug/Release, nested Results, try, handled closes, multiple failures |
| tests/ownership-counts | Permanent native lifecycle regression | Exact stdout, zero live allocations, no extra close or premature drop |
| proposals/pending-error-precedence.md | Keep the selected design with the fix | Independent exact-patch review |

## Alternatives
- Do nothing leaves documented precedence broken and accepted borrowed-return programs unverifiable.
- A close-only boolean/select guard leaves hidden owned return paths out of checker summaries and does not repair borrowed lifetime handling.
- Own every result of every close-bearing function unnecessarily copies borrowed success cases; preserve existing disjoint-case lending instead.
- Add runtime ownership tags or a new Error representation expands the language/ABI and is unnecessary for existing Result case variants.
- Suppress verifier errors or permit resource copies hides the defect and is rejected.

## Stages
- Confirm baseline behavior and verifier failures independently; retain all old branches and adverse results.
- Implement only after structural review; keep checker and lowering changes in one root-cause patch.
- Red/green tests pin body Error fields and owned identity, borrowed caller lifetime, success/first-close-error and complete reverse close traces.
- Include owned local try, borrowed Result relay, whole forwarding, generic instances, custom error incompatibility and consumed resource parameters.
- Run native lifecycle/count controls, cancellation/fault/constructor/stream regressions and exact-patch independent review.
- Run fmt,Clippy,workspace nextest,repo checks,conformance+parse,e2e and applicable protected exact-head CI before any qualified merge.
- Retain plain/success/error/I/O performance controls and adverse samples; no performance improvement is claimed.
