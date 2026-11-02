[Wiki](../index.md) › [Runtime](index.md)

# Text helpers: String methods in `.ms`, conversions in `@std/text.ms`

Verified: Go text-parity sweep (workstream 1); tests `tests/e2e/testdata/stdlib/string-text.ms`, `text.ms`, `unicode-categories.ms`.

- Whole-string helpers (`fields_by`, `equal_fold`, `count`, `trim_chars`, `contains_any`, `index_any`, `split_after`, `title`, `capitalize`, `map_chars`, `find_char`, `replace_each`) are plain `.ms` methods in `stdlib/string.ms`, no import needed. `fields` and scalar predicates already exist (`@std/unicode.ms`, `@std/data/utf8.ms`); a parallel PR landed them, so re-run `ms search_symbol` right before building.
- `@std/text.ms` holds `parse_bool`, `parse_int_radix`, `quote`, `quote_ascii`, `unquote`. Go's `FormatFloat` is `Float.to_fixed`/`to_exponential`/`to_precision`.
- Category predicates (`is_punctuation`, `is_symbol`, `is_mark`) use the regex `\p{..}` tables from `.ms`; no Rust added.
- `replace_each(Map[String, String])`: first key in map order wins at each position, replacements are not rescanned.
- `@std/string.ms` cannot import `@std/unicode.ms` (cycle); use `@std/internal/unicode.ms`.
- In string literals `\\u{` still starts an interpolation; write `\\u\{` and `\}`.

Apply when: adding text or scalar helpers. Verify: `ms test tests/e2e/testdata/stdlib/text.ms`.
