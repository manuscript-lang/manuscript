[Wiki](../index.md) › [Runtime](index.md)

# Newer stdlib direction needs checkout reconciliation

Decision: the stdlib request calls for consolidated grouping and one spelling per operation; optional limits/timeouts honored when supplied; removal of the speculative resource-pooling API; equality and hashing interfaces; and a priority queue. This supersedes the older derived-only equality preference.

Verified: canonical declarations, checker rules, conformance, and generated references implement this direction. Optional also has presence and extraction methods; keep routine absence handling available without requiring a match.

Apply when: changing library signatures, bounds/interfaces, queue APIs, grouping, examples, or documentation.
Evidence: [current declarations](../../stdlib/intrinsics.ms); [compiled Optional methods](../../tests/e2e/testdata/accept/optional-methods.ms).
Verify: inspect current declarations and called behavior against the latest direction. Preserve omitted/none/explicit-limit behavior and custom equality/hash coherence. Do not restore removed APIs from older documentation or another branch.

---
Topics: [Standard-library API shape](../topics/stdlib-api-shape.md)
