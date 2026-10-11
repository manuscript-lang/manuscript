+++
title = "Canonical formatting and generated views"
weight = 109
+++

# Canonical formatting and generated views

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Source is authoritative; the formatter supplies its canonical layout. Diagrams and explanations can be regenerated from it.

## Formatter contract

Formatting preserves program meaning and comments, uses four-space indentation, emits LF with a final newline, and is idempotent: formatting twice produces the same text. Invalid input produces diagnostics and no file write. `ms fmt file.ms` formats in place; `--check` reports changes with nonzero status and performs no write. The current canonical pass preserves token spellings and physical code lines, places one space around operators and after argument/type colons and commas, removes delimiter-adjacent spaces, and separates inline comments with two spaces. It collapses blank runs to one, removes leading/trailing blank lines, and preserves comment text while removing trailing whitespace. Comment-only indentation rounds down to a multiple of four. It does not rewrap lines. Golden and token-equivalence tests fix these choices. A valid rewrite is installed by a same-directory atomic rename.

Compilation and task creation never invoke AI implicitly. Model output enters through an explicit capability call and validation. A generated explanation cannot change compilation behavior or replace a source edit.

See [source layout](../../core-language/basics/syntax.md) and [explicit capability inputs](../../modules-and-capabilities/capabilities/authority.md).

[Next: Structural edits and revision guards](../source/structural-editing.md)
