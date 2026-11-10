#!/usr/bin/env bash
# Run from the repository root; artifacts use the permitted local workspace.+# These commands document the measured checkout/build sequence. Do not restore
# source over unrelated work. Save the five-line production patch separately
# when preparing baseline and candidate worktrees.
set -euo pipefail
source /workspace/map-rust/env.sh
evidence=/workspace/map-iteration-evidence

# Baseline at 6c9260f8c39a45c55a7f59f7df28bf373b6f97df, then candidate with patch.
# Run this block once on each revision with version=baseline or version=candidate.
version=${1:?baseline or candidate}
mkdir -p "$evidence/$version"
make build > "$evidence/$version/build.log" 2>&1
cp target/release/ms "$evidence/$version/ms"
for name in intersection intersection-strings; do
  "$evidence/$version/ms" build "bench/perf/map-runtime-audit/$name.ms" -o "$evidence/$version/$name"
done
"$evidence/$version/ms" build bench/perf/set-empty-relations/maps-control.ms -o "$evidence/$version/maps-control"

# After both builds, compile the driver once with the baseline compiler.
"$evidence/baseline/ms" build bench/tools/map_intersection_audit.ms -o "$evidence/focused-runner"
taskset -c 0 "$evidence/focused-runner" "$evidence/baseline/intersection" - "$evidence/baseline/samples" 5 200000
taskset -c 0 "$evidence/focused-runner" "$evidence/baseline/intersection" "$evidence/candidate/intersection" "$evidence/paired" 10 2000000
taskset -c 0 "$evidence/focused-runner" "$evidence/baseline/intersection-strings" "$evidence/candidate/intersection-strings" "$evidence/strings" 12 2000000 intersection
for spec in 'union empty 8' 'union empty 128' 'union disjoint 0' 'difference same 8' 'difference same 128' 'difference disjoint 1' 'difference holes 8' 'difference holes 65536'; do
  read -r mode pattern size <<< "$spec"
  taskset -c 0 "$evidence/focused-runner" "$evidence/baseline/intersection" "$evidence/candidate/intersection" "$evidence/focused/$mode-$pattern-$size" 20 20000000 "$mode" "$pattern" "$size"
done
# Existing Python runner reused unchanged; it refuses to overwrite its output.
taskset -c 0 python3 bench/perf/set-empty-relations/measure-maps.py "$evidence/baseline/maps-control" "$evidence/candidate/maps-control" "$evidence/paired-maps.json"
taskset -c 0 python3 bench/perf/set-empty-relations/focused-maps.py "$evidence/baseline/maps-control" "$evidence/candidate/maps-control" "$evidence/focused-maps.json"
taskset -c 0 python3 bench/perf/set-empty-relations/measure-maps.py "$evidence/candidate/maps-control" "$evidence/baseline/maps-control" "$evidence/reversed-maps.json"
"$evidence/baseline/ms" build bench/tools/map_lookup_audit.ms -o "$evidence/map-lookup-runner"
for spec in 'string_get 4096 5000 0' 'string_get 4096 38 4096' 'string_update 65536 11 256' 'int_update 128 100000 0' 'string_get 128 50000 16' 'string_update 4096 5000 0'; do
  read -r mode size repeats width <<< "$spec"
  taskset -c 0 "$evidence/map-lookup-runner" "$evidence/candidate/maps-control" "$evidence/baseline/maps-control" "$evidence/map-confirm/$mode-$size-$width" 24 "$mode" "$size" "$repeats" "$width"
done

cargo test --locked -p ms-rt map::tests
"$evidence/candidate/ms" test tests/e2e/testdata/stdlib/collections.ms
make verify-full
