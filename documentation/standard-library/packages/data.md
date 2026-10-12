+++
title = "Text, bytes, and collections"
weight = 49
+++

# Text, bytes, and collections

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

Use receiver operations for existing data: `text.split(separator: ",")`, `bytes.slice(start: 0, end: 4)`, `values.map(transform: transform)`, and `left.union(right)`. These operations have one public spelling. Standalone functions create or decode values, such as `from_scalars`, `filled`, `range`, `map_from_entries`, and `compile` for a regular expression.

| Group | Source module | Reference |
| --- | --- | --- |
| String operations and StringBuilder | `@std/string.ms` | [Text](../reference/string.md) |
| Bytes operations and BytesBuilder | `@std/bytes.ms` | [Bytes](../reference/bytes.md) |
| List, Map, Set and their builders | `@std/collections.ms` | [Collections](../reference/collections.md) |
| Local FIFO and priority queues | `@std/queues.ms` | [Queue contracts](../data-and-io/queues.md) |
| Equality and hashing interfaces | `@std/equality.ms` | [Equality rules](../../core-language/types/equality-and-hashing.md) |
| Base64 and hexadecimal encoding | `@std/encoding.ms` | [Encodings](../reference/encoding.md) |
| Binary numbers | `@std/binary.ms` | [Binary](../reference/binary.md) |
| Regular expressions | `@std/regex.ms` | [Regex](../reference/regex.md) |

List, Map and Set mutation is visible through aliases. `.clone()` makes a separate shallow copy. `sorted` returns a new list and accepts a comparator; there are no separate integer and string sorting helpers. Flatten a nested list with `flat_map` and an identity callback. Use `.at` for optional indexed access, including relative negative indexes on List and Bytes.

String indexing counts Unicode scalars rather than JavaScript UTF-16 code units. `replace` replaces one occurrence by default; `replace_all` replaces every occurrence. An explicit replacement cap is respected. `split` truncates to `max_parts` when supplied, including an empty result for zero, following JavaScript's split-limit behavior. Unicode normalization is explicit.

Regex uses Go's RE2 engine: captures and replacement syntax follow that engine, and backreferences/lookbehind are unsupported. Typed errors describe malformed inputs. [Limits and compatibility](stdlib-contracts.md) explains omittable budgets and the Node/JavaScript correspondence. [The source-backed reference](../reference/_index.md) gives every exact signature.
