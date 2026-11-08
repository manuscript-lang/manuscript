# One staging path for call arguments

## Summary

- Problem: each call form (source call, method value, interface call, native call, record construct, list mutator) decides on its own whether an evaluated owned argument stays registered for cleanup until the callee takes it. The rules differ per form (hold only when a later argument has `try`; exempt `Optional` temporaries from close; take before a bounds check), so a fix for one form leaves its siblings broken: #2890 then #2894, #2989 and #3027 are the same gap in other forms.
- Change: stage every owned argument at acquisition and release it at one point, the transfer into the callee or the store. Resources register with the runtime cleanup stack (`hold_resource_temp`), other values as statement temporaries (`hold_temp`). Forms migrate one at a time onto the shared helpers; per-form hold logic is deleted as each migrates.
- Verification: the MIR verifier already proves exactly one drop or move per owned value on every edge (`ms-mir/src/verify.rs`, run on lowered MIR and after every pass in debug builds). It cannot see a user `close` that never runs, so each stage adds fixtures that observe close order through a log file, run in the e2e corpus.

## Status

Stage 1 (this PR): `Optional` temporaries close at statement end (#2989), list `set`/`insert`/`replace` keep the incoming resource registered through every operand and the bounds check until `element_value` stores it (#3027), including a failing later operand. `replace` now checks its index in lowering, like `set`.

Stage 2: source calls, method values and interface calls stage an owned resource argument with `stage_arg` while later operands (or defaults) evaluate and take it back with `release_staged`, newest first (the cleanup stack discards a registration with every newer one). A staged value already moved out of its place is not read again (`refresh`).

Later stages, in order: record construct and the native call path onto the same helpers, then delete the `later_try` copies of the hold logic and the `copyelim` sub-passes whose copies lowering no longer emits.

## Problem

Measured on `c6fef864`: the `later_try`-style hold appears in `eval_args`, `native_args`, `construct`, `contract_call` and `mutator_call`, each with different conditions. The two reproductions in `tests/e2e/testdata/accept/` failed on `main` with `expected "1,", got ""` and `expected "2,1,", got "1,"`.

## Alternatives

- Do nothing: each form keeps leaking in its own way; about 40 issues in #2866 to #3027 are this shape.
- Validate before evaluating arguments: changes source evaluation order.
- Close only on the error branch: duplicates ownership policy and risks double close on success.
- Extend the verifier to model user `close` calls: closes are ordinary calls in MIR, so the check would need a resource role on every close; the e2e log-order fixtures cover it at lower cost.
