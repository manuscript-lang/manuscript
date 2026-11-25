[Wiki](../index.md) › [Language](index.md)

# A name is followed by its type with no colon

Decision (Chinmay, 2026-11-24): a typed name is `name Type`, optionally `= value`, in fields, parameters, enum payloads, `var` locals, typed immutable bindings (`x Int := v`) and generic bounds (`[T Comparable]`). `:` stays for argument labels, map entries, destructuring renames, and map entries; blocks are braced and arms use `=>` (see the braces page). Labels are kept; required parameters still precede defaulted ones.

Apply when: changing declaration parsing, diagnostics that print signatures, the formatter, the LSP hover, inlay and signature text, or any example.
Evidence: [proposal](../../proposals/braces-and-typed-names.md), [removed spellings](../../../documentation/core-language/removed-spellings.md), `parse_name_type` and `typed_binding_ahead` in `src/compiler/syntax`.
Verify: a statement starting `ident ident` is a declaration only when a `:=` or `=` follows at depth 0; an enum payload needs `(` touching the variant name; keywords stay usable as field names (`parse_member_name`); migrating by token position, not regex, is what keeps strings and comments intact.
