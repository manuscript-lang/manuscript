[Wiki](../index.md) › [Language](index.md)

# Parameterless main and imported host accessors

Decision: applications export `def main() -> Int` and import the standard services they use. The user explicitly deferred enforcement; the earlier exploration of `using`, scoped replacement, and manifest permissions is not an accepted implementation requirement. Ordinary service parameters remain available for helpers and source fakes.


Apply when: changing entrypoints, host roots, standard imports, tests, or authority documentation.
Evidence: [CLI contract](../../stdlib/process.ms), [host accessors fixture](../../tests/conformance/fixtures/e2e/accept/host-accessors.ms).
Verify: a parameterless entry runs; parameterized entries fail; imported accessors share roots across derived executions and imported helpers, while separate tests receive separate root wrappers.
