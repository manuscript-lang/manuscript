[Wiki](../index.md) › [Benchmarks and performance](index.md) › A block that moves into the growth region is freed, not cached

# A block that moves into the growth region is freed, not cached

A list built in a loop with a known trip count starts presized from the system allocator (8 MiB at 1M `Int`s). Its next doubling moves it into the growth region once and extends in place after. `realloc` freed the old block with `free`, which files a block up to 16 MiB in the large-block cache, where it stayed resident next to the live list: a 3M-element list peaked at 35 MB against Rust's 25 (27 after, 10M elements 90 to 82 against 80). The move now returns the block with `sys::free`.

- Peak memory is the resident set, not the committed size: measure it with `ru_maxrss` from `wait4` on a `posix_spawn`ed child (a forked Python child inherits the parent's maximum).
- A cache only helps a block that a later request of the same class will reuse. A buffer that grows leaves each size class behind for good.
