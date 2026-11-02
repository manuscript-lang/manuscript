[Wiki](../index.md) › [Tooling and docs](index.md)

# Select boundaries before scanning default ranges

Verified: computing an outline's EOF boundary for every declaration, then replacing it with the next declaration's boundary, rescans the same whitespace suffix for discarded results. Select the needed offset first, then trim once. Caching an expensive default before branching can preserve correct output while multiplying unnecessary work.

Apply when: deriving declaration ranges or simplifying expensive fallback expressions.
Evidence: [outline](../../crates/ms-lsp/src/symbols.rs), [suffix measurements and full JSON fingerprints](../../bench/perf/lsp-outline/results-2026-10-31.md).
Verify: last/nonlast declarations, existing outline snapshots, tiny/ordinary inputs, and whitespace/comment suffix controls; no output-range policy change.
