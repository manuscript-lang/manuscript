---
name: ast
description: Change Manuscript syntax nodes, shared traversal, lexer layout, strict parsing, or partial editor parsing while preserving positions and downstream coverage.
---

# AST and parsing

Use for `pkg/syntax/`, `pkg/lexer/`, `pkg/parser/`, or a new syntax consumer. Read [grammar](../../documentation/core-language/basics/grammar.md), [architecture](../../documentation/contributing/architecture.md), and [editor recovery lessons](../../.experts/tooling-and-docs.md#editor-recovery-must-preserve-delimiter-continuations).

- `pkg/syntax/ast.go` owns the untyped tree and positions; checked semantics belong in `pkg/checker/`. Keep syntax independent of compiler/runtime/editor machinery.
- Update `pkg/syntax/kinds.go` alongside parser, checker, lowering, formatting, and inspection consumers. `make repo-check` checks exhaustive checked/lowered kinds and package dependencies.
- Use `syntax.Visitor` in `pkg/syntax/walk.go` for executable traversal: defaults, interpolation, collections, closures, branches, and match bodies in source order. Do not manufacture statements to visit defaults. Types/patterns require appropriate separate handling.
- Preserve file identity and original offset/line/column positions. Check LF/CRLF and editor position conversion when slicing/recovery changes; synthetic repairs must not shift valid declarations.
- Exercise strict `parser.Parse` and editor `parser.ParsePartial`. Incomplete neighboring declarations must not erase multiline parameters or scopes. Use lexer continuation boundaries instead of splitting at lines/closing delimiters.
- Inline suites stop at enclosing delimiters, retain explicit returns, and enforce one statement/conditional branch per line. Follow current grammar rather than restoring blanket indentation restrictions.
- Route new shapes through [compiler](../compiler/SKILL.md) and [tooling](../tooling/SKILL.md). Verify traversal, accepted/rejected parsing, recovery, formatting idempotence, and affected editor scopes/navigation.
- Run affected syntax/lexer/parser tests. New parsing boundaries merit existing `FuzzParse`/`FuzzParsePartial` checks; preserve reproducible failures as regressions.
