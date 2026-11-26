# Large lists reserve capacity until growth stops refaulting

mimalloc has no remap, so a list that doubles to tens of MiB copies itself into never-touched pages at every step and faults each page twice: the 8M-element fill loop is 75.6 ms against Rust's 38.7 (glibc `mremap`), with the same instruction count. The owner decided against a remap tier (closed #7164, which measured `lz` -22%, `dispatch` -21%, `hashing` -12%) and chose a workaround: the `hashing`, `dispatch` and `lz` sources reserve their lists up front with `List[T](reserve: n)`. Issue #7169 names the removal condition: delete the `reserve:` calls once growth no longer copies and refaults on every platform and a run shows equal wall time without them.

- A growth factor of 4 (tried) takes the fill loop 79 to 66 ms and wastes up to 3x capacity; a transparent-huge-page hint on the new block (tried, not shipped) takes it to 43 ms on Linux only.
- Library buffers (`read_all`) grow the same way and are not fixed by a reserve in the benchmark source: `dedupe`, `jsonsum` and `report` carry that cost.
- The Rust, Go and JS ports of these benchmarks were not changed, so the gap to Rust for them excludes the growth cost.
