[Wiki](../index.md) › [Tooling and docs](index.md)

# Stream coordinates for ordered token batches

Verified: indexing line starts still recounts each line's UTF-16 prefix for every token, making long-line highlighting quadratic. A forward cursor scans only newly visited bytes. Its anchor must stay at an exact character boundary: backward and partial-byte queries use the original conversion without moving the anchor, so invalid-byte widths cannot contaminate the next valid position.

Apply when: rendering ordered batches of source positions or changing semantic tokens.
Evidence: [coordinate cursor and oracle test](../../crates/ms-lsp/src/text.rs), [strict/forgiving JSON regressions](../../crates/ms-lsp/tests/semantic_positions.rs), [measurements](../../bench/perf/lsp-semantic/results-2026-10-31.md).
Verify: every byte offset, partial UTF-8, oversize/backward/alternating queries, LF/CRLF, complete semantic JSON, and tiny/common/long-line controls.
