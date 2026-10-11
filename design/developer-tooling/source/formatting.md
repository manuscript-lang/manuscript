+++
title = "Canonical formatting and generated views"
weight = 109
+++

# Canonical formatting and generated views

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Source is authoritative; the formatter supplies its canonical layout. Diagrams and explanations can be regenerated from it.

## Formatter contract

Formatting preserves program meaning and comments, uses four-space indentation, emits LF with a final newline, and is idempotent: formatting twice produces the same text. Invalid input produces diagnostics and no file write. Exact choices for line wrapping, comment placement, and blank lines still need canonical snapshots.

Compilation and task creation never invoke AI implicitly. Model output enters through an explicit capability call and validation. A generated explanation cannot change compilation behavior or replace a source edit.

See [source layout](../../core-language/basics/syntax.md) and [explicit capability inputs](../../modules-and-capabilities/capabilities/authority.md).

[Next: Structural edits and revision guards](../source/structural-editing.md)
