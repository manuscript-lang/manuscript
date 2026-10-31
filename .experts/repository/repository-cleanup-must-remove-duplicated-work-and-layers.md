[Wiki](../index.md) › [Repository maintenance](index.md)

# Repository cleanup must remove duplicated work and layers

Decision: codebase cleanup should make the implementation easy to follow, with clear layer boundaries and one implementation of each shared behavior. Reorganizing files alone does not satisfy it: remove duplicated behavior and avoidable work before adding abstractions. Use the [simplify workflow](../../skills/simplify/SKILL.md) to apply this preference while preserving behavior unless a change is requested.

Verified: the lasting lessons from the Go-era cleanup are source-level. Semantic lint should use resolved identities instead of re-lexing names. One shared executable-syntax traversal (including defaults, closures, and interpolation) should serve checking and tooling. Editor requests should reuse their source index and resolve receivers without building a full inspection document. A source-only CLI command should stop at a checked program rather than lowering.

Apply when: organizing crates, extracting helpers, or adding another frontend/tooling pass.
Evidence: [shared traversal](../../crates/ms-syntax/src/visit.rs), [lint passes](../../crates/ms-tooling/src/lint/mod.rs), [architecture](../../documentation/contributing/architecture.md). The user message in "Organize repository layers" (chat `01a13b64-d01d-73d8-b318-7438b9ab402d`) establishes the preference.
Verify: identify the duplicate traversal, query, serialization, or forwarding path that disappears. Preserve source-level checking, default evaluation, module identity, and conformance; a smaller file tree alone is not evidence of simplification.

Verified: optimization works on a separate lowering view of checked source. Rewriting or removing AST nodes would break the node identities used by editor queries, lint, effects, and source maps. Parsing and resolution diagnostics travel with the syntax graph, including during recovery; folding a short-circuited expression must never let an invalid operand bypass checking.

Verified: a payload binder such as `error(NotFound)` can conceal a case name without a checking error. Advisory lint needs the checked identity before any sibling payload bindings enter scope, and each binder keeps its original position (rebased during partial parsing). Evidence: [binding lint](../../crates/ms-tooling/src/lint/bindings.rs), [pattern lint](../../crates/ms-tooling/src/lint/patterns.rs), [native binding versus separate payload handling](../../tests/e2e/testdata/accept/pattern-binding-capture.ms).

---
Topics: [Diagnostics and tooling](../topics/diagnostics-and-tooling.md) · [Cleanup and resources](../topics/cleanup-and-resources.md)
