+++
title = "Formatting"
weight = 1
+++

# Formatting

The source file defines the program. The formatter gives it a consistent layout, and tools can regenerate diagrams and explanations from it.

## Format a file

```sh
ms fmt file.ms
ms fmt file.ms --check
```

The first command formats in place. `--check` writes nothing and returns a nonzero status if formatting would change the file. Invalid input produces diagnostics and no write.

## Formatter contract

Formatting preserves program meaning and comments. It uses four-space indentation and LF line endings with a final newline. Formatting twice produces the same text; this property is called idempotence.

The current formatter applies these layout rules:

- Keep token spellings; wrap expressions using a soft limit of 88 columns.
- Keep short lists and callback signatures compact, and preserve authored spacing between match arms.
- Put one space around operators and after argument/type colons and commas.
- Remove spaces next to delimiters and put two spaces before inline comments.
- Collapse blank runs to one line and remove leading and trailing blank lines.
- Keep comment text but remove trailing whitespace.
- Round comment-only indentation down to a multiple of four.

See the [complete layout rules](../implementation.md#linting-and-formatting) for continuation groups and paragraph boundaries. Golden-output and syntax-equivalence tests verify these choices. A valid rewrite replaces the file through an atomic rename in the same directory.

## Generated explanations

Compilation and task creation never invoke AI implicitly. Model output enters through an explicit capability call and validation. A generated explanation cannot change compilation behavior or replace a source edit.

See [source layout](../../core-language/basics/syntax.md) and [capability inputs](../../standard-library/services.md).
