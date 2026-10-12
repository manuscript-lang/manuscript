---
name: language-design
description: Design or review Manuscript syntax, types, calls, imports, interfaces, errors, mutation, and execution semantics against current decisions and source examples.
---

# Language design

Use for semantic rules or proposals to add/remove syntax and language concepts. Apply [taste](../language-design-taste/SKILL.md) and read [language lessons](../../.experts/language.md).

- Start with a concrete program that is hard to express. Try existing functions, types, matching, and scoped cleanup before adding a concept.
- Read the relevant [core language](../../documentation/core-language/_index.md), [modules](../../documentation/modules-and-capabilities/_index.md), [cleanup](../../documentation/ownership-and-cleanup/_index.md), or [concurrency](../../documentation/concurrency/_index.md) chapter. Compare with [implementation coverage](../../documentation/implementation.md).
- Specify accepted/rejected source, inferred versus explicit types, arguments, evaluation order, aliasing, errors, and scope exits where relevant. Separate an accepted direction from verified implementation.
- Preserve explicit nominal relationships/conversions, one function kind, sequential calls, typed expected errors, and lexical cleanup unless the user changes those choices. Do not revive removed helpers under new names.
- Follow later corrections: labels may be omitted for single-parameter calls; multi-parameter calls name arguments. Defaults are callable permissions, not function-type identity. Inline suites retain explicit statements/returns and one conditional branch per line. Read current rules for exceptions.
- Keep equality/hashing separate from sharing and cleanup. Consult the [newer stdlib direction](../../.experts/runtime.md#newer-stdlib-direction-needs-checkout-reconciliation) before restoring older derived-bound requirements.
- Trace adopted rules through [ast](../ast/SKILL.md), [compiler](../compiler/SKILL.md), [tooling](../tooling/SKILL.md), [documentation](../documentation/SKILL.md), and [runtime](../runtime/SKILL.md) where execution changes.
- Implemented rules need acceptance/rejection, diagnostic, and observable native cases. Design-only work supplies acceptance cases and unresolved questions without claiming implementation.
