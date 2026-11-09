# Combination traversal

Build `main.ms` in Release, then pass the input length, chosen size, repetition
count and expected output count. Input construction is excluded from timing;
every iteration checks the output count and contributes to a printed checksum.

```sh
ms build bench/perf/combinations/main.ms --build-type Release -o /tmp/combinations
/tmp/combinations 10 3 10000 120
/tmp/combinations 16 8 50 12870
/tmp/combinations 1000000 1000000 1 1
```

Compare alternating baseline/candidate runs on the same machine. Include empty
and zero-size cases (`0 0 100000 1`, `5 0 100000 1`), ordinary combinations and
a full-size selection. Use the conformance tests for order and independent-copy
semantics; output count alone does not establish those properties.
