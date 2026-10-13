+++
title = "Text and collections"
weight = 5
+++

# Text and collections

Use receiver operations for existing data: `text.split(separator: ",")`, `bytes.slice(start: 0, end: 4)`, `values.map(transform: transform)`, and `left.union(right)`. These operations have one public spelling. Standalone functions create or decode values, such as `from_scalars`, `filled`, `range`, `map_from_entries`, and `compile` for a regular expression.

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

`map` transforms each element, `filter` keeps matching elements, and `flat_map` combines the lists returned by its callback. These operations return new lists. Callbacks run sequentially and may wait for operations.

Inside a function or test:

```manuscript
let labels = [1, 2].map(transform: fn(value: Int) -> String:
    return "item {value}"
)
let line = labels.join(separator: ", ")
# line is "item 1, item 2".
```

Import `List` from `@std/collections.ms` for the bracket literal. `find` and `find_index` stop at the first match and return an `Optional`; their `find_last` variants search from the end. `some` and `every` return a `Bool`; an empty list produces false and true respectively. `fold` and `fold_right` require an initial accumulator, which may have a different type from the elements. Sorting is stable and requires an explicit comparator.

## Map and set order

Maps and sets enumerate in insertion order, while equality ignores order. Replacing an existing map key retains its position; removing and adding it puts it at the end. `map_from_entries` uses the last value for duplicate keys and keeps the first insertion position. `merge` mutates the receiving map, replacing matching values and appending new keys.

`with_default_from` calls its creation function only when the key is absent. Set algebra returns new sets: left-side traversal order is retained, followed by right-only values where applicable. Keys and set elements must satisfy [Hashable](../core-language/types/equality-and-hashing.md).

## Text and regular expressions

String indexing counts Unicode scalars. `replace` replaces one occurrence by default; `replace_all` replaces every occurrence. An explicit replacement cap is respected. `split` truncates to `max_parts` when supplied, including an empty result for zero; `n` separators give `n + 1` parts, so empty text with a nonempty separator gives one empty part, while an empty separator splits into scalars and gives none for empty text. A negative `max_parts` or `max_replacements` faults with a message naming the operation and parameter, because those operations return plain values. `upper` and `lower` apply locale-independent full Unicode case mapping, matching JavaScript, Python, and Rust: `"ß".upper()` is `"SS"`, `"ﬁ".upper()` is `"FI"`, `"ΑΣ".lower()` ends in final sigma `ς`, and `"İ".lower()` is `i` followed by U+0307. Mapping can change the scalar length. Unicode normalization is explicit.

Regex uses RE2 syntax. Backreferences and lookbehind are unsupported; malformed patterns return typed errors. See [common contracts](contracts.md) for optional budgets and the [API reference](reference/_index.md) for exact signatures.
