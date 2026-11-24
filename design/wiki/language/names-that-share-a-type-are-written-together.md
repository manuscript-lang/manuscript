[Wiki](../index.md) › [Language](index.md)

# Names that share a type are written together

Decision (Chinmay, 2026-11-24): `width, height Int` declares two names of one type in type fields, function parameters and enum payloads. A default applies to each name (`x, y Float = 0.0`). It is sugar: the parser reads the type and default again for each name, so the checker and tools see separate fields or parameters. Closure parameters (`fn(a, b)`, `(a, b) =>`) stay untyped lists, so grouping applies only where a type is required. Local bindings do not group.

Apply when: parsing declarations, writing signature printers (hover, inlay hints, signature help show one parameter per name), or changing the formatter.
Evidence: `parse_group_names` in `src/compiler/syntax/parse_type.c`, [named types](../../../documentation/core-language/types/named-types.md), fixture `tests/conformance/fixtures/e2e/accept/grouped-names.ms`.
Verify: `(a, b)` alone is never a group; a group needs a name directly followed by a type start after the last comma; each name gets its own type node and default expression.
