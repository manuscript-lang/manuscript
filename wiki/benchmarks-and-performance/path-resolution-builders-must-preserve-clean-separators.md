[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Path resolution builders must preserve clean separators

Verified: POSIX resolution copied its growing prefix for every relative part.
Starting at the last absolute anchor and appending tails once removes that
quadratic work, but inserting a redundant slash after the anchor sends ordinary
paths through normalization's slower dirty-path logic. Preserve existing
separators, build strings directly rather than converting bytes back to UTF-8, and
avoid constructing a builder when every surviving relative part is empty.

Apply when: changing lexical path resolution. Validate every input for NUL before
ignoring superseded parts, and retain explicit Windows dialect semantics.
Evidence: [paired measurements and rejected forms](../../bench/perf/path-resolve/README.md).
Verify: called `path.ms` conformance, long tails, and empty/one/four-part controls
with A/A variation; a long-tail win alone did not qualify the earlier forms.
