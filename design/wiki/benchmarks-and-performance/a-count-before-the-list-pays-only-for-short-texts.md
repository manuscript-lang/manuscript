# A count before the list pays only for short texts

Verified (2026-11-25): #7084 made `split` count its pieces first so the list is one allocation. Against the run before it, grep over a 22 MB log went from 159 M to 196 M instructions (+24%), logstats +8.7%, dedupe +5.5%, report +3.4%: the count is a second pass over every byte (about 1.6 instructions per byte), while the doublings it replaces cost a few instructions per piece and a realloc per doubling, and a long text has one piece per tens of bytes. `split_at_pattern` counts only texts of at most 4,096 bytes (a 21-piece split stays one allocation) and grows by doubling for longer ones: all four back to within 0.2% of before.

Apply when: a runtime primitive adds a pre-pass to size its output. Compare against the doubling cost per piece on a large input in `bench/perf/suite`, not only the allocation count on a small one.
