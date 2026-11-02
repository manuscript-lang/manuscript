[Wiki](../index.md) › [Repository maintenance](index.md)

# Repository cleanup must remove duplicated work and layers

Decision: codebase cleanup should make the implementation easy to follow, with clear layer boundaries and one implementation of each shared behavior. Reorganizing files alone does not satisfy it: remove duplicated behavior and avoidable work before adding abstractions. Use the [simplify workflow](../../skills/simplify/SKILL.md) to apply this preference while preserving behavior unless a change is requested.

Apply when: organizing crates, extracting helpers, or adding another frontend/tooling pass.
Evidence: [shared traversal](../../crates/ms-syntax/src/visit.rs), [lint passes](../../crates/ms-tooling/src/lint/mod.rs), [architecture](../../documentation/contributing/architecture.md). The user message in "Organize repository layers" (chat `01a13b64-d01d-73d8-b318-7438b9ab402d`) establishes the preference.
Verify: identify the duplicate traversal, query, serialization, or forwarding path that disappears. Preserve source-level checking, default evaluation, module identity, and conformance; a smaller file tree alone is not evidence of simplification.
