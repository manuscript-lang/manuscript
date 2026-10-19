# ms-rt micro-benchmarks vs Go

Same machine, same run (4 cores, shared), `crates/ms-rt/tests/bench/run.sh`. Nanoseconds per element; Go figures are
`ns/op` of the benchmark divided by the element count (2,000,000 pushes and sort elements, 1,000,000 map operations, 200,000 concats).

| operation | ms-rt | Go | note |
| --- | --- | --- | --- |
| list push (Int) | 10 | 75 | Go `append` including GC growth |
| stable sort (Int, comparator call) | 108 | 497 | Go `sort.SliceStable` |
| map insert (Int) | 186 | 254 | insertion ordered; Go map is unordered |
| map get (Int) | 210 | 106 | **slower than Go**: ordered slots plus a separate index cost two cache misses per hit |
| string concat + length | 23 | 26 | one allocation each |

Known gap: map lookup. A follow-up can store a hash tag in the index and keep small Int/String keys inline in the index
to remove the second miss; generated code does not depend on that layout (only `MapVal.len` is public).
