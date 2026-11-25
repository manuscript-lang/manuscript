[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Completion finds the import spot once per request

Every importable name that matched the word called `lsp_import_insertion`, which scans the whole document for line starts, import ends and the header. Completion on `data/html.ms` (5,700 lines) took 265 ms, of which 77% was this scan repeated per offer; the analysis itself is about 80 ms. `lsp_import_site` now runs once per request (kept on the `Completer`) and `lsp_import_text` builds each edit; completion is 85 ms.

Rule: work that depends on the document, not on the item, is computed before the item loop. Profile a request with `callgrind --trace-children=yes`; the server runs in a forked worker.
