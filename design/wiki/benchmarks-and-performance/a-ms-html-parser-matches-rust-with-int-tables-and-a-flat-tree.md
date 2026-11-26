# A Manuscript HTML parser matches Rust with Int tables and a flat tree

The HTML tokenizer and tree builder moved from Rust to `src/stdlib/data/html.ms` at equal speed (`bench/perf/html/`). What made it fast:

- Tags and attribute names become Int atoms once; insertion modes, scopes and rule classes are Int constants, and decisions are `match` on Int literals. String `match` and module constants (rebuilt on each access) were the slow paths.
- The tree is parallel Int lists (kind, atom, parent, first child, next sibling), not nodes; the open-element stack carries parallel mark arrays. Nodes become `HtmlNode` once at the end.
- There are no bitwise operators; use rule classes and small tables instead of masks.
- Moving a value out of a field needs `.clone()` under the one-owner model; plan for it in token buffers.
- Only entity decoding stays native (`src/runtime/std/html_entity.c`, the entity table).

The oracle is the recorded Go output in `tests/lang/projects/html-oracle/assets/oracle.tsv`.
