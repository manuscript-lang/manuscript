---
name: runtime
description: Implement or review Manuscript native execution, resources, cancellation, cleanup, concurrent work, runtime dispatch, and standard-library declarations, bindings, and API design.
---

# Runtime

Use for `pkg/runtime/`, `internal/hostos/`, `pkg/stdlib/*.ms`, `bindings.json`, or lowering that changes execution. Read [runtime lessons](../../.experts/runtime.md), [cleanup](../../documentation/core-language/cleanup/_index.md), and [concurrency](../../documentation/concurrency/_index.md).

- State observable result/error identity, evaluation order, aliasing, cancellation, close, join, and use-after-close behavior before editing.
- Keep sharing, resource lifetime, and work lifetime separate. Passing references needs no sharing proof and does not extend resource lifetime. Explicit synchronization protects complete shared updates; local Queue has no implicit locks/waiting/close.
- Trace admission → acquisition → delivery → scope exit/cancellation → close. Cancelled undelivered acquisitions release resources; stale guards/aliases cannot access reused handles. Consult newer stdlib direction before retaining APIs scheduled for removal.
- Exercise return/error/fault/cancellation/break/continue across cleanup scopes. Cleanup completes before joins return; close accounts for admitted work without deadlocking callbacks/reentry.
- Keep data mutable and cloning shallow; native resource handles cannot be cloned. Guard validation/synchronization covers actual operations and reads where required.
- Native I/O remains interruptible after descriptor metadata access. Completeness includes blocked I/O, concurrent close, bounded streaming, and shutdown, beyond successful return values. Process `stdin`/`stdout` reads and writes need not be cancellable (the user dropped that item).
- Concurrency stays API-shaped: do not expose channels. Waiting between tasks belongs in standard types and `Synchronized` guard operations.
- Map and Set are hash-indexed and iterate in insertion order. Key and element types must be `Hashable`; an unhashable key type is a compile error, never a linear-scan fallback. `Equal` and `Hashable` are ordinary source interfaces.
- Preserve declared error types/cases/causes and checked binding identities.
- Include new runtime/platform sources in standalone bundles and implementation identity; aliases must agree when runtime files are merged. Verify emitted programs as well as ordinary package compilation.
- Keep implementations needing `net/http`, `crypto/tls`, gopsutil, or similar heavy dependencies in `//go:build !ms_lean` files, and list their standard modules in the compiler's full-runtime set; `TestLeanRuntimeImplementsLeanModules` checks the lean runtime still serves every other module.
- Run affected runtime tests and called native conformance; concurrency/lifetime changes need relevant race checks and bounded coordinated cancellation/shutdown cases. Report material untested platform limits.

## Standard library

For standard APIs (intrinsic/native members, design), read [declaration ownership](../../pkg/stdlib/README.md), [contracts](../../documentation/standard-library/contracts.md), [runtime lessons](../../.experts/runtime.md), and [taste](../language-design-taste/SKILL.md).

- Inspect [newer stdlib direction](../../.experts/runtime.md#newer-stdlib-direction-needs-checkout-reconciliation) and current source first. Distinguish requested changes from shipped interfaces/bounds, removals, optional limits, and scheduling consolidation.
- Give each operation one appropriate module/spelling. Cover units, defaults, errors, streaming, mutation, edge cases, and cancellation; use Manuscript's execution model.
- Pick the failure mode by the [one rule](../../documentation/standard-library/contracts.md#choosing-a-failure-mode): absence is `Optional`, invalid external data is `Result`, a violated documented precondition faults with operation, argument, and valid range. Mutators take verbs (`set`, `remove`, `add`); copies keep past-tense or noun names. Do not restore the removed copy-sounding aliases (`with_value`, `without`, `with_entry`).
- Every standard type and function carries a doc comment, and a type's comment includes a short usage example; it appears in the generated reference.
- Audit omitted, `none`, valid, and invalid explicit limits/timeouts. The latest direction makes them optional and honored when supplied; do not impose mandatory limits without new direction. Document resource consequences and errors.
- Checked `.ms` source owns public signatures. Trace declaration → binding → checker call/receiver rules → native dispatch → called source tests → editor information → generated reference.
- Use domain-specific expected errors, preserving causes/concrete interface receivers. Generic boundaries use explicit matching/views; do not silently flatten Results or recreate convenience error-mapping APIs.
- Rename/removal covers imports, constructors, methods, aliases, bindings, dispatch, fixtures, virtual documents, generated pages/downloads, and guides. Respect the user's removal scope for historical/rejection mentions.
- Keep collection, synchronization, scheduling, and cleanup contracts explicit. Defaults agree across source metadata, native arity, function values, completion, and docs.
- Verify declaration/native ABI comparisons and called conformance, including invalid inputs/edges. Pair with [tooling](../tooling/SKILL.md); regenerate `make docs` and run applicable [documentation checks](../documentation/SKILL.md).
