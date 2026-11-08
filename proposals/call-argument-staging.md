# One staging path for call arguments

## Summary

- Problem: each call form (source call, method value, interface call, native call, record construct, list mutator) decides on its own whether an evaluated owned argument stays registered for cleanup until the callee takes it. The rules differ per form (hold only when a later argument has `try`; exempt `Optional` temporaries from close; take before a bounds check), so a fix for one form leaves its siblings broken: #2890 then #2894, #2989 and #3027 are the same gap in other forms.
- Change: stage every owned argument at acquisition and release it at one point, the transfer into the callee or the store. Resources register with the runtime cleanup stack (`hold_resource_temp`), other values as statement temporaries (`hold_temp`). Forms migrate one at a time onto the shared helpers; per-form hold logic is deleted as each migrates.
- Verification: the MIR verifier already proves exactly one drop or move per owned value on every edge (`ms-mir/src/verify.rs`, run on lowered MIR and after every pass in debug builds). It cannot see a user `close` that never runs, so each stage adds fixtures that observe close order through a log file, run in the e2e corpus.

## Status

Stage 1 (this PR): `Optional` temporaries close at statement end (#2989), list `set`/`insert`/`replace` keep the incoming resource registered through every operand and the bounds check until `element_value` stores it (#3027), including a failing later operand. `replace` now checks its index in lowering, like `set`.

Stages 2 and 3 landed on `main` from other work while this was in review (#2984, #2992, #3004, #3052): source, interface, function-value and list-mutator calls now hold owned resource arguments through later operands, so this change adds no further staging helper. What it adds is below.

## Problem

Measured on `c6fef864`: the `later_try`-style hold appears in `eval_args`, `native_args`, `construct`, `contract_call` and `mutator_call`, each with different conditions. The two reproductions in `tests/e2e/testdata/accept/` failed on `main` with `expected "1,", got ""` and `expected "2,1,", got "1,"`.

## Alternatives

- Do nothing: each form keeps leaking in its own way; about 40 issues in #2866 to #3027 are this shape.
- Validate before evaluating arguments: changes source evaluation order.
- Close only on the error branch: duplicates ownership policy and risks double close on success.
- Extend the verifier to model user `close` calls: closes are ordinary calls in MIR, so the check would need a resource role on every close; the e2e log-order fixtures cover it at lower cost.

## Stage 3 findings

Counting how often each `copyelim` sub-pass changes a module over the e2e and conformance corpora (453 and 3887 fixtures): `borrow_local_copies` 396, `move_dead_sources_across_blocks` 327, `move_dead_sources` 318, `borrow_str_phis` 215, `borrow_str_copies_across_blocks` 124, `run_func` 90, `unbox_dead_sources` 62, `unbox_dead_options` 5, `borrow_opt_str_reads` 1. Most still fire because they also elide the copy of a written `.clone()` whose source dies, which is an optimization, not a lowering hack. `borrow_opt_str_reads` (one firing, a refcount-era shape) is deleted. `make copy-check` failed on `tools/copy-check.ms:62` (`env` moved in a loop); fixed with `env.clone()`, and it now reports 0 lowering copies over 717 programs.

## Close failures and bounds checks (#3075, #3076)

A mutator that discards a resource entry (`set`, `remove`, `splice`, map `add`/`remove`) closes it in place; a failed close faulted at once, leaving the entry in the container so the unwind closed it again. The failure is now recorded (`defer_close_failures`) and the fault comes after the mutation removed the entry (`fault_deferred_close`), so each entry closes once and every entry of a `splice` is attempted.

`insert`, `replace` and `remove` took the list out of its variable before the bounds check, so a fault left the variable's cleanup with an empty slot; Windows then closed nothing in the list (#3076). They now check the index while the list is still in the variable (`precheck_list_index`).
