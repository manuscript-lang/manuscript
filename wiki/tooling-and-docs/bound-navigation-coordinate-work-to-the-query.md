[Wiki](../index.md) › [Tooling and docs](index.md)

# Bound navigation coordinate work to the query

Verified: converting every expression or reference offset by rescanning source prefixes makes navigation quadratic. Resolve a cursor once for exact single-line token matches; preserve the UTF-16 fallback for invalid or mismatched snapshots. Batch result positions with a shared line index, bounded by the last needed offset so an early reference does not scan an unrelated file suffix.

Apply when: changing hover, navigation, references, or batches of source-coordinate conversions.
Evidence: [navigation](../../crates/ms-lsp/src/nav.rs), [fallback regressions](../../crates/ms-lsp/tests/hover_fallback.rs), [reference ranges](../../crates/ms-lsp/tests/reference_order.rs), [measurements](../../bench/perf/lsp/results-2026-10-31.md).
Verify: LF/CRLF, same-line emoji, half-open ranges, truncated/invalid snapshots, alternating files and missing modules; interleave tiny, common, large and early-reference controls.

Freeze the complete analyzed source world for comparisons, including embedded
standard declarations and dependencies. An old-main index fingerprint mismatch
must stop the run. Reconstruct a same-main baseline by reversing only the measured
production patches; retain output assertions rather than filtering changed facts.
The [matched preflight](../../bench/perf/tooling-preflight-2026-10-31/README.md)
records this correction and keeps the rejected comparison separate. Required CI
and an actual merged-main replay still gate completion.
