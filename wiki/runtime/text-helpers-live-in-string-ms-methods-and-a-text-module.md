[Wiki](../index.md) › [Runtime](index.md)

# Text helpers: String methods in `.ms`, conversions in `@std/text.ms`

Verified: Go text-parity sweep (workstream 1); tests `tests/e2e/testdata/stdlib/string-text.ms`, `text.ms`, `unicode-categories.ms`.

- Whole-string helpers (`fields_by`, `equal_fold`, `count`, `trim_chars`, `contains_any`, `index_any`, `split_after`, `title`, `capitalize`, `map_chars`, `find_char`, `replace_each`) are plain `.ms` methods in `stdlib/string.ms`, no import needed. `fields` and scalar predicates already exist (`@std/unicode.ms`, `@std/data/utf8.ms`); a parallel PR landed them, so re-run `ms search_symbol` right before building.
- `@std/text.ms` holds `parse_bool`, `quote`, `quote_ascii`, `unquote`. Go's `FormatFloat` is `Float.to_fixed`/`to_exponential`/`to_precision`.
- Category predicates (`is_punctuation`, `is_symbol`, `is_mark`) use the regex `\p{..}` tables from `.ms`; no Rust added.
- `replace_each(Map[String, String])`: first key in map order wins at each position, replacements are not rescanned. An empty map can clone the input without materializing scalar lists; keep the explicit clone so the result remains independently owned. Test exact Unicode/NUL bytes and source reassignment, and measure small nonempty-map hit/miss controls before changing this shortcut.
- `@std/string.ms` cannot import `@std/unicode.ms` (cycle); use `@std/internal/unicode.ms`.
- In string literals `\\u{` still starts an interpolation; write `\\u\{` and `\}`.
- `quote` and `quote_ascii` must escape both braces and literal-forbidden bidi controls; verify their output can be parsed as source, as well as round-tripped through `unquote`. Unicode escape payloads require 1 to 6 ASCII hexadecimal digits: the signed integer parser alone also accepts invalid `+41` and `-0` payloads.
- `var x = param` inside a stdlib function aliases the parameter, so callers lose their String (an old radix parser consumed `text`). Derive with `drop`/`take` into a `var`, or `.clone()`; check by calling the function twice with one variable.
- Regex template caps check each borrowed literal/capture before appending it; expanding first can copy 128 MiB for a zero-byte cap (#3289). Capped expansion is differential-tested against upstream syntax, including Unicode names, unfinished braces and braced `${+1}`; uncapped calls keep the upstream expander. The cap bounds output bytes, not all matching allocations or String capacity.

Apply when: adding text or scalar helpers. Verify: `ms test tests/e2e/testdata/stdlib/text.ms`.
