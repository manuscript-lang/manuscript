[Wiki](../index.md) › [Tooling and docs](index.md)

# Project review must keep library internals behind their boundary

Verified: inspection deliberately includes bundled standard source modules. Feeding every inspection entity into a project review makes even the hello project show hundreds of library entities before its own entry point. Review facts and diagrams exclude standard declarations while retaining calls into them as external boundaries and imports as dependencies. An unscoped call view also needs roots for disconnected recursive groups: selecting only declarations with no callers silently loses them.


Apply when: changing inspection consumers, review facts, or diagram roots.
Evidence: [fact collection](../../crates/ms-tooling/src/collect.rs), [CLI regressions](../../crates/ms-cli/tests/review_diagram.rs), [view regressions](../../crates/ms-tooling/tests/review.rs), [output contract](../../documentation/developer-tooling/implementation.md#review-report).
Verify: a program importing process arguments has one project entry point in its review and keeps the standard call as a diagram leaf; recursive groups remain visible without `--entity`; an explanation's stable ID selects the same finding in a diff-marked JSON diagram.

Git diff paths use Git's C-style byte quoting, not JSON or Manuscript strings. Decode quoted UTF-8 octal bytes before stripping side prefixes or comparing identities; otherwise an ordinary Unicode filename looks like a rename. Reject malformed or non-UTF-8 paths rather than substituting a different filename. Parser and CLI review/diagram regressions cover quoted paths.

Unified-diff EOF markers carry side-specific source information. Preserve them when reconstructing the base or deleted content, and validate the head terminator rather than inheriting it blindly. Treat an empty file as zero lines, not a synthetic trailing line ([diff regressions](../../crates/ms-tooling/tests/review.rs), [#3171](https://github.com/manuscript-lang/manuscript/issues/3171)).
