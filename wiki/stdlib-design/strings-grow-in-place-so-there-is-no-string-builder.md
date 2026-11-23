[Wiki](../index.md) › [Standard-library design](index.md)

# Strings grow in place, so there is no StringBuilder

Decision (Chinmay, 2026-11-23): `StringBuilder` is removed. Build text with `var text = ""` and `text += piece`; a string records its spare room, so appends need no builder. Measured: 3 million appends took 0.063 s with `+=` and 0.07 s with the builder.

- Hand the text over and start again by moving it out and assigning a new empty string: `pieces.append(text)` then `text = ""`. This replaces `drain()`, and works on `var` fields too.
- `BytesBuilder` stays (Chinmay, 2026-11-23): `Bytes` has no `+=`. `x = x.concat(y)` on an owned, dying `x` now grows the buffer in place (`msrt_bytes_concat_grow`, chosen by `opt_strfuse`): 300k appends took 3.5 s before and about 0.1 s after.
- Wiki pages that mention `StringBuilder.append` fast paths (`strfast`, `strbuilder_append`) describe code that was deleted; the string append fast path is `opt_appendfast`.
