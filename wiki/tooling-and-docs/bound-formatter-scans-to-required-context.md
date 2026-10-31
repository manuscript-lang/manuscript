# Bound formatter scans to required context

A long flow exposed two multiplied scans: checking each leading dot searched its
whole item prefix, and each empty call measured an overlapping suffix. At 2,048
steps the formatter took seconds for a small valid file.

Track only preceding significant-token and pipe facts within the current
comma-separated item. Ignore comments/layout, reset on an outer comma, and keep
group children out of the parent's prefix. Preserve rendered line tracking as a
separate fact; comments and group closing lines still affect it.

Suffix width is used only to decide whether a group exceeds the fixed line
width. Once a safe lower bound exceeds that width, further measurement cannot
change the decision. Count only nonempty tokens the flat renderer emits and
preserve newline/comment/clause/nonempty-group stops. Keep exact rendering for
short tails; a byte count is not a safe Unicode character-width lower bound.

Compare complete baseline output around the cutoff and stop boundaries, and
measure tiny ordinary calls and lists as well as long flows. A fast long case
does not excuse common-path regressions. See the [measured matrix](../../bench/perf/formatter-flow/results-2026-10-31.md).
