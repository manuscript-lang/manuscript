[Wiki](../index.md) › [Language](index.md)

# Multi-line text is one token that line-based passes must mask

Decision: the user chose `"""` (interpolating) plus `r"""` (raw) literals, indent stripped to the closing line, to end `\"`, `\{`, `\}` escaping in JSON fixtures (#2167). This replaced the earlier "no raw or multiline literals" rule.

Verified: the formatter, the suite-header pass and expression layout all work per source line, so a token that spans lines is corrupted unless it is swapped for a one-line placeholder first. `format` masks each such token and restores it shifted with the line it lands on. A new multi-line construct needs the same treatment, and a position inside the literal needs a line and column computed from its text.

Apply when: changing text literals, the lexer's string scanning, or any line-based formatter or editor pass.
Evidence: [literal rules](../../documentation/core-language/basics/text-and-bytes.md#multi-line-and-raw-literals); `crates/ms-syntax/tests/multiline.rs`.
Verify: a formatted file that holds a `"""` literal inside a wrapped call parses to the same value and formats to itself.
