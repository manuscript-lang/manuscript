---
name: language-design
description: Design or review Manuscript syntax, types, calls, imports, interfaces, errors, mutation, and execution semantics against current decisions and source examples.
---

# Language design

Use for semantic rules or proposals to add/remove syntax and language concepts. Apply [taste](../language-design-taste/SKILL.md) and read [language lessons](../../.experts/language.md).

- Start with a concrete program that is hard to express. Try existing functions, types, matching, and scoped cleanup before adding a concept.
- Read the relevant [core language](../../documentation/core-language/_index.md), [modules](../../documentation/core-language/modules/_index.md), [cleanup](../../documentation/core-language/cleanup/_index.md) chapter. Compare the documented rule with current source and tests.
- Specify accepted/rejected source, inferred versus explicit types, arguments, evaluation order, aliasing, errors, and scope exits where relevant. Separate an accepted direction from verified implementation.
- Preserve explicit nominal relationships/conversions, one function kind, sequential calls, typed expected errors, and lexical cleanup unless the user changes those choices. Do not revive removed helpers under new names.
- Follow later corrections: invocation labels are optional for every declared parameter; bind unlabeled arguments (including bare identifiers) by position, keep deterministic mixed binding, and written evaluation order. Callback function-type labels retain their identity. Defaults are callable permissions, not function-type identity. Inline suites retain explicit statements/returns and one conditional branch per line. Read current rules for exceptions.
- Values have one owner and move at their last use; `var` marks mutation at the declaration and the call (`f(var xs)`), and `.clone()` makes an explicit deep copy. See the [ownership rules](../../crates/ms-check/OWNERSHIP.md) and [Rust toolchain differences](../../documentation/contributing/rust-toolchain.md#differences-users-can-see). Check [references](../../documentation/core-language/types/references.md) against current behavior before relying on shared-alias wording.
- Keep equality/hashing separate from sharing and cleanup. `Equal` and `Hashable` are ordinary interfaces: usable as bounds and in `impl`, with Map/Set keys required to be `Hashable`. Consult the [newer stdlib direction](../../.experts/runtime.md#newer-stdlib-direction-needs-checkout-reconciliation) before restoring older derived-bound requirements.
- Module-level `let NAME = <constant expression>` is allowed and evaluated per use; see the [constants lesson](../../.experts/language.md#module-level-constants-are-use-site-evaluations-not-stored-values).
- Block syntax stays indentation-based. Braces were weighed and showed no measurable speed or first-try benefit, so do not propose them for speed.
- Trace adopted rules through [compiler](../compiler/SKILL.md) (syntax included), [tooling](../tooling/SKILL.md), [documentation](../documentation/SKILL.md), and [runtime](../runtime/SKILL.md) where execution changes.
- Implemented rules need acceptance/rejection, diagnostic, and observable native cases. Design-only work supplies acceptance cases and unresolved questions without claiming implementation.
