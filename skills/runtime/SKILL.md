---
name: runtime
description: Implement or review Manuscript native execution, resources, cancellation, cleanup, runtime dispatch, and standard-library declarations, bindings, and API design.
---

# Runtime

Use for `pkg/runtime/`, `internal/hostos/`, `pkg/stdlib/*.ms`, `bindings.json`, or lowering that changes execution. Read [runtime lessons](../../.experts/runtime.md), [cleanup](../../documentation/core-language/cleanup/_index.md).

- State observable result/error identity, evaluation order, aliasing, cancellation, close, join, and use-after-close behavior before editing.
- Keep sharing, resource lifetime, and work lifetime separate. Passing references needs no sharing proof and does not extend resource lifetime. Explicit synchronization protects complete shared updates; local Queue has no implicit locks/waiting/close.
- Trace admission → acquisition → delivery → scope exit/cancellation → close. Cancelled undelivered acquisitions release resources; stale guards/aliases cannot access reused handles. Consult newer stdlib direction before retaining APIs scheduled for removal.
- Exercise return/error/fault/cancellation/break/continue across cleanup scopes. Close does not deadlock callbacks or reentry.
- Keep data mutable and cloning shallow; native resource handles cannot be cloned. Guard validation covers actual operations and reads where required.
- Native I/O remains interruptible after descriptor metadata access. Completeness includes blocked I/O, concurrent close, bounded streaming, and shutdown, beyond successful return values. Process `stdin`/`stdout` reads and writes need not be cancellable (the user dropped that item).
- Concurrency is intentionally absent from the language and standard library until it is redesigned from the ground up; do not add task, scheduler, lock, or channel APIs without a new user direction.
- Map and Set are hash-indexed and iterate in insertion order. Key and element types must be `Hashable`; an unhashable key type is a compile error, never a linear-scan fallback. `Equal` and `Hashable` are ordinary source interfaces.
- Preserve declared error types/cases/causes and checked binding identities.
- Include new runtime/platform sources in standalone bundles and implementation identity; aliases must agree when runtime files are merged. Verify emitted programs as well as ordinary package compilation.
- The standard declarations in `pkg/runtime/std_*_gen.go` come from `make stdgen`; change the `.ms` declaration, regenerate, and implement the signature the `rtcheck` build reports. See [runtime conventions](../../documentation/contributing/runtime-conventions.md).
- Run affected runtime tests and called native conformance; lifetime changes need bounded cancellation/shutdown cases. Report material untested platform limits.

## Rust runtime

The Rust runtime is `crates/ms-rt`, `ms-rt-abi`, and one `crates/ms-std-*` crate per native module, embedded through `ms-native`; `unsafe` is confined to `ms-rt`, `ms-rt-abi`, and `ms-cli/src/process.rs`. Values are owned and moved, not shared, so aliasing and shallow `clone()` assumptions in the Go runtime do not carry over ([differences](../../documentation/contributing/rust-toolchain.md#differences-users-can-see)). Native standard identities still come from `pkg/stdlib/*.ms` and `bindings.json`; a signature change reaches `pkg/runtime` and the Rust crate.

## Standard library

For standard APIs (intrinsic/native members, design), read [declaration ownership](../../pkg/stdlib/intrinsics.ms), [contracts](../../pkg/stdlib/intrinsics.ms), [runtime lessons](../../.experts/runtime.md), and [taste](../language-design-taste/SKILL.md).

- Inspect [newer stdlib direction](../../.experts/runtime.md#newer-stdlib-direction-needs-checkout-reconciliation) and current source first. Distinguish requested changes from shipped interfaces/bounds, removals, optional limits, and scheduling consolidation.
- Give each operation one appropriate module/spelling. Cover units, defaults, errors, streaming, mutation, edge cases, and cancellation; use Manuscript's execution model.
- Pick the failure mode by the [one rule](../../pkg/stdlib/intrinsics.ms): absence is `Optional`, invalid external data is `Result`, a violated documented precondition faults with operation, argument, and valid range. Mutators take verbs (`set`, `remove`, `add`); copies keep past-tense or noun names. Do not restore the removed copy-sounding aliases (`with_value`, `without`, `with_entry`).
- Every standard type and function carries a doc comment, and a type's comment includes a short usage example; it appears in the generated reference.
- Audit omitted, `none`, valid, and invalid explicit limits/timeouts. The latest direction makes them optional and honored when supplied; do not impose mandatory limits without new direction. Document resource consequences and errors.
- Checked `.ms` source owns public signatures. Trace declaration → binding → checker call/receiver rules → native dispatch → called source tests → editor information → generated reference.
- Use domain-specific expected errors, preserving causes/concrete interface receivers. Generic boundaries use explicit matching/views; do not silently flatten Results or recreate convenience error-mapping APIs.
- Rename/removal covers imports, constructors, methods, aliases, bindings, dispatch, fixtures, virtual documents, generated pages/downloads, and guides. Respect the user's removal scope for historical/rejection mentions.
- Keep collection, synchronization, scheduling, and cleanup contracts explicit. Defaults agree across source metadata, native arity, function values, completion, and docs.
- Verify declaration/native ABI comparisons and called conformance, including invalid inputs/edges. Pair with [tooling](../tooling/SKILL.md); regenerate `make docs` and run applicable [documentation checks](../documentation/SKILL.md).
