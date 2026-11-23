# src/compiler/syntax

Layer L2: source text to syntax tree and back. Allowed includes: see `src/layers.txt`.

| Files | Owns |
| --- | --- |
| `pos.h`, `token.h/.c`, `ast.h` | positions, the diagnostic record, tokens, the tree (same node shapes and ids as the Rust `ms-syntax`) |
| `lex*.c`, `lex.h` | the lexer: scanning, layout tokens, text and interpolation |
| `parse*.c`, `parse.h` | the parser (`ms_parse`) |
| `format*.c`, `format.h` | the formatter (`ms_format`): line passes, imports, comments, expression layout, compaction |
| `walk.c/.h` | tree visitor and `ms_expr_start` |
| `diag_codes.c`, `diag.h`, `diag_json.c/.h`, `message.c/.h` | stable diagnostic codes, JSON text of diagnostics, message building |

Gate: `ms run tools/conform-run.ms -- --phase parse` (the `fmt <entry> --check --json` and `fmt <entry>` commands).
