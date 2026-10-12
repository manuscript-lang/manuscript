---
name: runtime
description: Implement or review Manuscript native execution, mutable values, resource acquisition, cancellation, cleanup, concurrent work, and runtime dispatch.
---

# Runtime

Use for `pkg/runtime/`, `internal/hostos/`, or lowering that changes execution. Read [runtime lessons](../../.experts/runtime.md), [cleanup](../../documentation/core-language/cleanup/_index.md), and [concurrency](../../documentation/concurrency/_index.md).

- State observable result/error identity, evaluation order, aliasing, cancellation, close, join, and use-after-close behavior before editing.
- Keep sharing, resource lifetime, and work lifetime separate. Passing references needs no sharing proof and does not extend resource lifetime. Explicit synchronization protects complete shared updates; local Queue has no implicit locks/waiting/close.
- Trace admission → acquisition → delivery → scope exit/cancellation → close. Cancelled undelivered acquisitions release resources; stale guards/aliases cannot access reused handles. Consult newer stdlib direction before retaining APIs scheduled for removal.
- Exercise return/error/fault/cancellation/break/continue across cleanup scopes. Cleanup completes before joins return; close accounts for admitted work without deadlocking callbacks/reentry.
- Keep data mutable and cloning shallow; native resource handles cannot be cloned. Guard validation/synchronization covers actual operations and reads where required.
- Native I/O remains interruptible after descriptor metadata access. Parity includes blocked I/O, concurrent close, bounded streaming, and shutdown, beyond successful return values.
- Preserve declared error types/cases/causes and checked binding identities. Pair public changes with [standard-library](../standard-library/SKILL.md).
- Include new runtime/platform sources in standalone bundles and implementation identity; aliases must agree when runtime files are merged. Verify emitted programs as well as ordinary package compilation.
- Run affected runtime tests and called native conformance; concurrency/lifetime changes need relevant race checks and bounded coordinated cancellation/shutdown cases. Report material untested platform limits.
