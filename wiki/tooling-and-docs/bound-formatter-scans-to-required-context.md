# Bound formatter scans to required context

A long flow exposed two multiplied scans: checking each leading dot searched its
whole item prefix, and each empty call measured an overlapping suffix. At 2,048
steps the formatter took seconds for a small valid file.

Track only preceding significant-token and pipe facts within the current
comma-separated item. Ignore comments/layout, reset on an outer comma, and keep
group children out of the parent's prefix. Preserve rendered line tracking as a
separate fact; comments and group closing lines still affect it.

Keep suffix-width measurement exact and preserve its newline, comment, clause,
and nonempty-group stops. Any shortcut must pass ordinary-list controls as well
as long-flow workloads before it is retained.

Compare complete baseline output around the cutoff and stop boundaries, and
measure tiny ordinary calls and lists as well as long flows. A fast long case
does not excuse common-path regressions. See the [measured matrix](../../bench/perf/formatter-flow/results-2026-10-31.md).
