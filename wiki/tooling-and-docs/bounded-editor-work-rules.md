[Wiki](../index.md) › [tooling-and-docs](index.md)

# Bounded editor work rules

Formatter, navigation and token-batch work stays bounded to the query and required context. Each section is one lesson.

## Bound formatter scans to required context

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

Restore multiline literal and block-comment placeholders in source order with a
forward cursor and an append-only output. Searching and replacing each marker
from the beginning rescans and shifts an increasingly large document. Compute
indentation from the restored prefix, not the masked input: an earlier multiline
literal on the same line can change the prefix seen by a later placeholder.

Choose a source-absent marker sequence, not a character from a fixed alphabet.
Valid Unicode payloads can contain every BMP private-use character (#3193).
Use a compact numbered fallback, not a marker proportional to the longest text
run that multiplies masked-source size across spans. Check payload preservation
and idempotence for both block comments and multiline text, with LF and CRLF.

## Bound navigation coordinate work to the query

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

The mismatched-snapshot fallback must also use one shared line index and cursor position per query: three prefix scans per expression took 19 s for the first hover after an edit in a 36,000-line file (#3137).

The name-table limit counts growth past the size settled after the last start, not absolute size: with an absolute 1 MiB cap, one large document's own names made every request drop all caches and reload the standard library (0.9 s per hover, 13 ms cached; #3136).

## Select boundaries before scanning default ranges

Verified: computing an outline's EOF boundary for every declaration, then replacing it with the next declaration's boundary, rescans the same whitespace suffix for discarded results. Select the needed offset first, then trim once. Caching an expensive default before branching can preserve correct output while multiplying unnecessary work.

Apply when: deriving declaration ranges or simplifying expensive fallback expressions.
Evidence: [outline](../../crates/ms-lsp/src/symbols.rs), [suffix measurements and full JSON fingerprints](../../bench/perf/lsp-outline/results-2026-10-31.md).
Verify: last/nonlast declarations, existing outline snapshots, tiny/ordinary inputs, and whitespace/comment suffix controls; no output-range policy change.

## Stream coordinates for ordered token batches

Verified: indexing line starts still recounts each line's UTF-16 prefix for every token, making long-line highlighting quadratic. A forward cursor scans only newly visited bytes. Its anchor must stay at an exact character boundary: backward and partial-byte queries use the original conversion without moving the anchor, so invalid-byte widths cannot contaminate the next valid position.

Apply when: rendering ordered batches of source positions or changing semantic tokens.
Evidence: [coordinate cursor and oracle test](../../crates/ms-lsp/src/text.rs), [strict/forgiving JSON regressions](../../crates/ms-lsp/tests/semantic_positions.rs), [measurements](../../bench/perf/lsp-semantic/results-2026-10-31.md).
Verify: every byte offset, partial UTF-8, oversize/backward/alternating queries, LF/CRLF, complete semantic JSON, and tiny/common/long-line controls.
