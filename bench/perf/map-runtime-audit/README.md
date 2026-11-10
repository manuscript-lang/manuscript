# Runtime Set intersection benchmarks

`intersection.ms` checks exact ordered Int results for intersection, union and
difference. `intersection-strings.ms` checks owned String intersection results
and consumes them through a metadata Map. `empty-intersection-repro.ms` checks
1,000 empty-right intersections with a caller-supplied left size.

Build baseline and candidate compilers with the same pinned toolchain and normal
`make build` path. Build each producer with its corresponding compiler in LLVM
Release mode. Keep binaries, build metadata, raw samples and logs outside tracked
source; do not commit individual investigation records.

From the repository root, with existing compiler paths and an external output
directory (use a fresh directory for each run):

```sh
BEFORE_MS=/path/to/baseline/ms
AFTER_MS=/path/to/candidate/ms
OUT=/tmp/map-intersection-run
mkdir -p "$OUT"
for producer in intersection intersection-strings; do
  "$BEFORE_MS" build "bench/perf/map-runtime-audit/$producer.ms" --build-type Release -o "$OUT/$producer-before"
  "$AFTER_MS" build "bench/perf/map-runtime-audit/$producer.ms" --build-type Release -o "$OUT/$producer-after"
done
"$BEFORE_MS" build bench/tools/map_intersection_audit.ms --build-type Release -o "$OUT/runner"
"$OUT/runner" "$OUT/intersection-before" "$OUT/intersection-after" "$OUT/int" 10 2000000
"$OUT/runner" "$OUT/intersection-strings-before" "$OUT/intersection-strings-after" "$OUT/string" 12 2000000 intersection
```

The driver takes `BEFORE AFTER_OR_DASH OUTPUT PAIRS WORK [MODE [PATTERN [SIZE]]]`.
Use `-` for a baseline-only run. It covers sizes 0/1/8/128/4096/65536 and empty,
equal, disjoint, one-shared-member and deleted-slot inputs. It alternates paired
order, writes a warmup as `trial=-1`, and validates exits, stderr and checksums.
Exclude warmups from summaries and retain every measured pair. Optional filters
support longer confirmation runs; reverse the two binaries in a separate run
and preserve their version labels. Pin both versions to the same allowed CPU
where supported, without concurrent builds or benchmarks.

For neighboring Map controls, build
[`maps-control.ms`](../set-empty-relations/maps-control.ms) with both compilers
and build [`map_lookup_audit.ms`](../../tools/map_lookup_audit.ms) once. Its
arguments are `BEFORE AFTER OUTPUT PAIRS MODE SIZE REPEATS PREFIX_WIDTH`;
for example, `before after /tmp/map-control 24 string_update 65536 11 256`.
Both drivers retain internal elapsed time and whole-process wall time.

The empty-right fix and regression tests shipped in
[PR #3505](https://github.com/manuscript-lang/manuscript/pull/3505), with
[required CI passing](https://github.com/manuscript-lang/manuscript/actions/runs/42841453689).
Keep its measurement limits when interpreting new runs: synthetic workload
times include result consumption, and String runs can include metadata lookup
and last-use cleanup; they are not isolated intersection latency. The historical
long-string Map overwrite control retained an uncertain 2.7% median slowdown
(13/24 pairs), with direction changes across longer and reversed runs. Neither
host variation nor binary layout was established as its cause. This is not a
universal speedup or performance-parity claim. The old inventory reference uses
removed syntax and remains non-comparable; instruction counts and page faults
were not collected. Re-measure both small and large neighboring controls on the
same machine and build settings before qualifying another optimization.
