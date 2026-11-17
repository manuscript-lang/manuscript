[Wiki](../index.md) › [Benchmarks and performance](index.md) › Platform parity means functional parity

# Platform parity means functional parity

Decision (Chinmay, 2026-11-17): parity across Linux, macOS and Windows is functional. The same program gives the same results everywhere, and every platform gets the best fast path its own system offers (for example Linux huge pages for large blocks, see [the huge-page page](a-block-above-the-cached-range-asks-for-huge-pages.md)). A fast path is not mirrored with a weaker mechanism where a platform has no equivalent, and a missing equivalent is not a reason to drop the path on the platform that has one.

This is about performance mechanisms only. It does not relax the rule that tests are never skipped, gated or no-opped on a platform without asking the owner.

Apply when: adding a platform-specific speedup, or deciding whether a perf change needs a matching macOS or Windows path.
