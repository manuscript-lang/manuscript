[Wiki](../index.md) › [Language](index.md)

# String conversion is available on every value

Decision: the user requested conversion with `to_string()` on everything. This supersedes the previous restriction of interpolation to scalars. Conversion is available in unconstrained generic code and uses the same representations as interpolation; ordinary type compatibility at assignment, call, and return boundaries remains explicit.


Apply when: changing interpolation, member resolution, formatting, or editor member queries.
Evidence: [canonical conversion rules](../../documentation/core-language/basics/text-and-bytes.md#converting-values-to-string); [source conformance](../../tests/e2e/testdata/accept/to-string.ms).
Verify: a record and an unconstrained `T` both support `.to_string()` and direct interpolation; a closed resource converts without invoking an operation; passing that record directly to a String parameter is still rejected.
