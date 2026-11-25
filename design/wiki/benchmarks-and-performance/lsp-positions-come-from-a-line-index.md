[Wiki](../index.md) › [Benchmarks and performance](index.md)

# LSP passes find positions through a line index

`lsp_position` counts newlines from the top of the file, so a pass that asks for a position per token or per symbol is quadratic, and the semantic-token pass also scanned a list per name. Semantic tokens of a 26,000-line file took 26 s, of `data/html.ms` 1 s; the outline 913 ms. A per-source line table (`LspLines`, binary search) and a table of resolved kinds by byte offset made them 98 ms, 15 ms and 19 ms. Completion repeated the replaced range per item; it is computed once.

Rule: a loop over tokens, symbols or occurrences uses `lsp_lines_position`; `lsp_position` is for a single answer. Measure each request on a file of 5,000 and 25,000 lines. Completion cost was not positions: see [import offers](completion-finds-the-import-spot-once.md).
