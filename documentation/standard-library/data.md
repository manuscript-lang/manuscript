+++
title = "Text and collections"
weight = 5
+++

# Text and collections

Use receiver operations for existing data: `text.split(separator: ",")`, `bytes.slice(start: 0, end: 4)`, `values.map(transform: transform)`, and `left.union(right)`. Standalone functions create or decode values, such as `from_scalars`, `filled`, `range`, `map_from_entries`, and `compile` for a regular expression.

| Group | Source module | Reference |
| --- | --- | --- |
| String operations and StringBuilder | `@std/string.ms` | [Text](reference/string.md) |
| Bytes operations and BytesBuilder | `@std/bytes.ms` | [Bytes](reference/bytes.md) |
| List, Map, Set and their builders | `@std/collections.ms` | [Collections](reference/collections.md) |
| Local FIFO and priority queues | `@std/queues.ms` | [Queue contracts](../concurrency/queues.md) |
| Equality and hashing interfaces | `@std/equality.ms` | [Equality rules](../core-language/types/equality-and-hashing.md) |
| Base64 and hexadecimal encoding | `@std/encoding.ms` | [Encodings](reference/encoding.md) |
| Binary numbers | `@std/binary.ms` | [Binary](reference/binary.md) |
| Regular expressions | `@std/regex.ms` | [Regex](reference/regex.md) |

List, Map and Set mutation is visible through aliases. `.clone()` makes a separate shallow copy. `sorted` returns a new list and accepts a comparator; there are no separate integer and string sorting helpers. Flatten a nested list with `flat_map` and an identity callback. Use `.at` for optional indexed access, including relative negative indexes on List and Bytes.

## Transform and search lists

`take(count:)` returns a shallow copy of the first `count` elements; `drop(count:)` returns a shallow copy after them. Counts above `length()` are clamped: taking copies the whole list, dropping returns an empty list. Zero takes an empty list or drops nothing; a negative count produces a programming fault naming the operation, parameter and original count. Both return fresh mutable List storage even for empty or whole-list copies, preserve element order and payload references, and leave the receiver unchanged. They are explicit copy operations and do not change loop or callback traversal behavior.

`map` transforms each element, `filter` keeps matching elements, and `flat_map` combines the lists returned by its callback. These operations return new lists. Callbacks run sequentially and may wait for operations.

Inside a function or test:

```manuscript
let labels = [1, 2].map(transform: fn(value: Int) -> String:
    return "item {value}"
)
let line = labels.join(separator: ", ")
# line is "item 1, item 2".
```

Import `List` from `@std/collections.ms` for the bracket literal. `find` and `find_index` stop at the first match and return an `Optional`; `find_last` and `find_last_index` search from the end. `index_of` and `last_index_of` search by equality. `for_each` runs a sequential callback and returns Unit. `some` and `every` return a `Bool`; an empty list produces false and true respectively. `fold` and `fold_right` require an initial accumulator, which may have a different type from the elements. Sorting is stable and requires an explicit comparator. See [search and enumeration](../core-language/types/collections.md#search-and-enumeration) for callback labels, entry shapes, and Set relation operations.

## Map and set order

Maps and sets enumerate in insertion order, while equality ignores order. Replacing an existing map key retains its position; removing and adding it puts it at the end. `map_from_entries` uses the last value for duplicate keys and keeps the first insertion position. `merge` mutates the receiving map, replacing matching values and appending new keys.

`with_default_from` calls its creation function only when the key is absent. Set algebra returns new sets: left-side traversal order is retained, followed by right-only values where applicable. Keys and set elements must satisfy [Hashable](../core-language/types/equality-and-hashing.md).

## Text and regular expressions

String indexing and search count Unicode scalars. The [text rules](../core-language/basics/text-and-bytes.md#indexing-and-character-boundaries) specify units and the negative, clamped, swapped, and strict slice bounds. String operations return new text and leave the receiver unchanged.

| String operations | Behavior |
| --- | --- |
| `contains`, `starts_with`, `ends_with` | Test exact text contents without normalization. |
| `trim`, `trim_start`, `trim_end` | Remove Unicode whitespace from both ends, the start, or the end. Whitespace is U+0009–U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, and U+3000. |
| `upper`, `lower` | Apply locale-independent full Unicode case mapping; the scalar length can change. |
| `scalar_length`, `scalar_values` | Count Unicode scalars or return their integer code points. |
| `length`, `is_empty`, `chars`, `reverse` | Count/test text, collect one String per scalar, or reverse scalar order; returned lists have fresh storage. |
| `compare` | Return -1/0/1 in case-sensitive lexical scalar order without locale or normalization. |
| `lines` | Split LF/CRLF terminators, retaining interior empty lines and standalone CR; omit an extra trailing item. See the exact [text rules](../core-language/basics/text-and-bytes.md#indexing-and-character-boundaries). |
| `pad_start`, `pad_end` | Repeat and truncate `padding` on scalar boundaries until `target_length` scalars are reached. A shorter target or empty padding leaves the text unchanged. Negative targets return `InvalidInput`. |
| `replace_first` | Replace the first occurrence by default (omitted or `none` cap); a supplied `max_replacements` can replace more than one occurrence, and zero leaves text unchanged. Negative caps fault. `replace` remains a compatible spelling with identical defaults, caps, and faults. |
| `replace_n` | Replace at most the required `max_replacements: Int` nonoverlapping literal occurrences. Zero leaves text unchanged; negative counts retain replace's programming fault. This count is not a UTF-8 byte budget. |
| `replace_all` | Replace every nonoverlapping occurrence. Return `StringError.LimitExceeded` if the UTF-8 output exceeds a supplied `max_bytes`, or `InvalidInput` for a negative budget. |
| `split` | Split on exact separators and truncate to a supplied `max_parts`; zero returns no parts and negative limits fault. Empty text split on a nonempty separator returns `[""]`; an empty separator splits into scalars, giving no parts for empty text. |

For a finite cap, use `text.replace_n(old: "a", new: "b", max_replacements: 2)`. Current `replace_first` is a transitional compatibility spelling: its retained count parameter can replace more than one match. Its signature remains supported; a future strict first-only shape requires a separate reviewed migration. `replace_n` has no additional output-byte/allocation budget, and replacement text can grow the result; `replace_all` provides a separate byte-budgeted operation.

An empty `old` in `replace_first` (or `replace`), `replace_n` and `replace_all` matches before the first scalar and after each scalar, including the end. Replacement does not scan newly inserted text. `repeat`, `normalize`, `pad_start`, and `pad_end` also accept optional UTF-8 output budgets: omitted or `none` budgets impose no cap, zero permits only empty output, negatives return `StringError.InvalidInput`, and exceeding a supplied budget returns `StringError.LimitExceeded`. Even unchanged padding results must fit the supplied budget. Normalization accepts exactly the case-sensitive strings `NFC`, `NFD`, `NFKC`, or `NFKD`; other forms return `StringError.InvalidInput`.

Use `NormalizationForm.Nfc`, `Nfd`, `Nfkc`, or `Nfkd` from `@std/string.ms` to select a form with a checked alternative. Its `normalize(text, max_bytes = none)` operation shares the existing String implementation, UTF-8 byte budgets, errors, and cancellation. Canonical forms compose/decompose canonically equivalent text; compatibility forms also normalize compatibility characters such as ligatures.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import NormalizationForm from "@std/string.ms"
import panic from "@std/faults.ms"

test "typed Unicode normalization":
    let text = NormalizationForm.Nfkc.normalize("ﬁ", max_bytes: 2).unwrap()
    if text != "fi": return panic("compatibility normalization")
```

Negative `max_parts` and `max_replacements` fault with a message naming the operation and parameter, because these operations return plain values. Full case mapping includes `"ß".upper()` as `"SS"`, `"ﬁ".upper()` as `"FI"`, final sigma `ς` at the end of `"ΑΣ".lower()`, and `"İ".lower()` as `i` followed by U+0307.

Regex uses RE2 syntax. Backreferences and lookbehind are unsupported; malformed patterns return typed errors. See [common contracts](contracts.md) for optional budgets and the [API reference](reference/_index.md) for exact signatures.

`Regex.replace_all(text:, replacement:, max_bytes:)` replaces every nonoverlapping match with literal text; `$1` does not expand a capture. `Regex.replace` remains a compatible spelling. Omitted or `none` byte budgets impose no cap, zero permits only empty output, negative budgets return `RegexError.InvalidInput`, and output exceeding a supplied budget returns `RegexError.LimitExceeded`. The UTF-8 budget includes unmatched input, even when no match occurs.

## Byte operations

| Bytes operations | Behavior |
| --- | --- |
| `length`, `is_empty`, `at` | Count bytes, test emptiness, or read an unsigned byte; negative lookup indexes are relative to the end. |
| `contains`, `starts_with`, `ends_with` | Test byte subsequences, prefixes, or suffixes. |
| `index_of`, `last_index_of` | Return the first or last matching byte offset, or `none`; empty searches match at zero or `length()` respectively. |
| `split` | Split exact binary separators into a fresh List of immutable Bytes views. `max_parts` truncates returned parts; omitted/`none` is unlimited, zero returns no parts, negatives fault. |
| `slice` | Select a strict half-open byte range under the [slice rules](../core-language/basics/text-and-bytes.md#half-open-slices). |
| `with_value`, `reversed`, `reverse`, `concat`, `clone` | Return Bytes without changing the receiver. `reverse` remains a compatible spelling for `reversed`. `with_value` accepts relative negative indexes; an invalid index or a value outside 0–255 faults. |
| `values` | Return a fresh mutable `List[Int]` of bytes; `values(data:)` remains available as a free function. |
| `to_text` | Decode valid UTF-8 or return `none`. |

Bytes stay immutable even when a native slice shares storage. Construction and extraction copy values, as described in [encoding and parsing](../core-language/basics/text-and-bytes.md#encoding-and-parsing).

`Bytes.split` preserves leading, interior and trailing empty parts. An empty separator yields one Bytes per byte, and gives no parts for empty data; a nonempty separator gives one empty part for empty data. It never decodes UTF-8, so separators can split a multibyte character or invalid text. A cap discards later parts instead of retaining an unsplit remainder: `Bytes([1, 0, 2, 0, 3]).split(Bytes([0]), max_parts: 2)` returns `[Bytes([1]), Bytes([2])]`. Returned Lists have independent mutable storage, while their immutable Bytes may share the input storage. Changing a result with `with_value` creates new Bytes and leaves the input and other parts unchanged.

## Base64 encoding

`base64_encode(data: bytes)` and `base64_decode(text: "/w==")` use the standard alphabet by default. Pass `url_safe: true` for the URL-safe alphabet (`_w==` for the same byte). Decoding still validates the selected alphabet and an explicit `max_bytes` output budget; zero is a supplied budget.
