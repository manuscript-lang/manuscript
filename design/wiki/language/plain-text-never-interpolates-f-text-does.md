[Wiki](../index.md) › [Language](index.md)

# Plain text never interpolates; `f"..."` text does

Decision (Chinmay, 2026-11-15): `"..."` and `"""` never interpolate, so braces are plain characters (`"{"` is one brace, JSON needs no escape). `f"..."` and `f"""` interpolate `{expr}`; a literal brace there is `\{` or `\}`. `\{` in plain text is an error that says braces are plain. `r"..."` is unchanged and there is no `rf`. This replaced "every `"..."` interpolates, there is no `f` prefix", which kept making agents escape braces in JSON and regexes.

Rejected: a warning when a plain string holds `{name}` for a variable in scope (Chinmay: not needed), and any automatic fix that rewrites braces. Verified: lowering is unchanged, since `f` text parses to the same `Text` parts.

A nested literal inside `{...}` interpolates only if it is itself `f"..."`. The `f` is part of the string token, so scanners that find literals by their opening quote (formatter, editor, grammars) must also recognise `f"` and `f"""`. `tools/f-strings.ms` rewrites old-syntax source and Markdown fences.

Apply when: changing the lexer's text scanning, editor/LSP literal scanners, grammars, or writing Manuscript examples (insert values with `f"..."`).
Evidence: [text and bytes](../../../documentation/core-language/basics/text-and-bytes.md#interpolation); `tests/conformance/fixtures/e2e/accept/f-text-and-plain-braces.ms`.
