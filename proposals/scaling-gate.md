# Scaling gate

## Problem

About 30 bugs (#2853-55, #2874, #2924, #2930, #2937-40, #2993, #3001, #3032-33) were passes or stdlib containers that rescan or copy per unit: lastuse, loopslot, the formatter, completion, API docs, SortedMap, String index, `replace_each`. Each was found by hand and its scaling numbers recorded in an issue. Nothing fails when a pass goes superlinear again.

## Proposed change

`tools/scaling-check.ms` (`make scaling-check`, a gate step in `rust-checks`) generates inputs of 1k, 10k and 100k units and compares ratios, not wall time:

- Compile shapes: a long function, many locals, a long interpolation, many impls, many functions, many branches and a big literal, each through `ms check` and `ms emit`.
- Runtime: `tests/scaling/containers.ms` times List, Map, Set, SortedMap, String build, scan and `replace_each` phases itself at 10k and 100k, so compile time does not enter.
- A measurement fails when `(t100k - t1k) / (t10k - t1k)` exceeds `SCALING_BOUND` (default 30). Linear work gives about 10, n log n about 12, quadratic about 100. Subtracting the 1k time removes process and standard-library start-up; a floor on the denominator keeps sub-noise phases from inflating the ratio.

First run on this checkout: every measurement is under 22x, so none of the earlier offenders has regressed. The highest are many_functions emit (about 20x) and many_impls (12 to 19x), whose wall time is above linear only from cache effects: callgrind instruction counts per function are constant from 5k to 40k functions, so there is nothing algorithmic to fix.

## Alternatives considered

- Wall-time budgets: they depend on the runner and break on a slow one. Ratios do not.
- Instruction counts under callgrind: more stable, but not available on macOS and Windows, and the gate must run on all three.
- Doing nothing: each cluster of bugs keeps costing a round of manual measurement.

## Testing

`ms run tools/scaling-check.ms` passes with 24 measurements on Linux with the release and debug `ms`. A temporary quadratic rescan in a pass would raise its ratio toward 100 and fail the bound.
