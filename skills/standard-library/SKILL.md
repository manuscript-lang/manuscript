---
name: standard-library
description: Design, implement, consolidate, or remove Manuscript standard APIs across declarations, native bindings, runtime behavior, editor support, and generated docs.
---

# Standard library

Use for `pkg/stdlib/*.ms`, `bindings.json`, intrinsic/native members, or API parity/design. Read [declaration ownership](../../pkg/stdlib/README.md), [contracts](../../documentation/standard-library/packages/contracts.md), [runtime lessons](../../.experts/runtime.md), and [taste](../language-design-taste/SKILL.md).

- Inspect [newer stdlib direction](../../.experts/runtime.md#newer-stdlib-direction-needs-checkout-reconciliation) and current source first. Distinguish requested changes from shipped interfaces/bounds, removals, optional limits, and scheduling consolidation.
- Give each operation one appropriate module/spelling. Requested Node.js/JavaScript parity includes units, defaults, errors, streaming, mutation, edge cases, and cancellation; use Manuscript's execution model instead of copying Promise/callback families.
- Audit omitted, `none`, valid, and invalid explicit limits/timeouts. The latest direction makes them optional and honored when supplied; do not impose mandatory limits without new direction. Document resource consequences and errors.
- Checked `.ms` source owns public signatures. Trace declaration → binding → checker call/receiver rules → native dispatch → called source tests → editor information → generated reference.
- Use domain-specific expected errors, preserving causes/concrete interface receivers. Generic boundaries use explicit matching/views; do not silently flatten Results or recreate convenience error-mapping APIs.
- Rename/removal covers imports, constructors, methods, aliases, bindings, dispatch, fixtures, virtual documents, generated pages/downloads, and guides. Respect the user's removal scope for historical/rejection mentions.
- Keep collection, synchronization, scheduling, and cleanup contracts explicit. Defaults agree across source metadata, native arity, function values, completion, and docs.
- Verify declaration/native ABI comparisons and called conformance, including invalid inputs/edges. Pair with [runtime](../runtime/SKILL.md) and [tooling](../tooling/SKILL.md); regenerate `make docs` and run applicable [documentation checks](../documentation/SKILL.md).
