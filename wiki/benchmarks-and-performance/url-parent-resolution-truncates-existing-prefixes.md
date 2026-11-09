# URL parent resolution truncates existing prefixes

Resolving `..` removes the last segment of an accumulated URL path. Copying the whole prefix before each removal makes a long parent walk quadratic. Search the existing bytes for their final separator and truncate in place instead; each removed segment is then scanned once.

Keep root handling, repeated slashes, escaped dot text and trailing slashes unchanged. The separator search excludes the initial slash, so its offset must be shifted by one when truncating the original buffer. Preserve the existing `first` flag transition when no inner separator remains.

Use [the URL parent benchmark](../../bench/perf/url-parents/README.md) with increasing depths and one-parent, four-parent, plain-relative and dot-relative controls. Compare exact outputs as well as scaling; do not replace URI semantics with filesystem normalization.
