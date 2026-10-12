+++
title = "JavaScript built-in coverage"
weight = 61
+++

# JavaScript built-in coverage

[Standard library guide](../_index.md) · [Package coverage](coverage.md) · [Implemented signatures](../reference/_index.md)

The inventory follows MDN's [JavaScript reference](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference), particularly [Array](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array), [String](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String), [Map](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Map), [Set](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Set), and [Number](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Number). Rows identify runnable equivalents; names and contracts follow Manuscript's type system. Deprecated HTML string wrappers and prototype machinery are excluded from the useful data API.

## List / Array

Import `List` for bracket literals. All updates return new values. Callbacks run sequentially and may suspend; use the separate `parallel_map` API for joined concurrency.

| JavaScript surface | Manuscript equivalent | Contract |
| --- | --- | --- |
| `length`, indexed access, `at` | `length()`, `get(index:)`, `at(index:)` | `get` rejects negative indexes; `at` counts from the end; missing values are `Optional` |
| `concat`, `push`, `unshift` | `concat(values:)`, `append(value:)`, `prepend(value:)` | Immutable updates; concat accepts a homogeneous list |
| `pop`, `shift` | `last()` / `first()` plus `without(index:)` | Retrieval and removal are explicit operations |
| `includes`, `indexOf`, `lastIndexOf` | `contains(value:)`, `index_of(value:)`, `last_index_of(value:)` | Element type must satisfy `Equal`; missing indexes are `none` |
| `find`, `findLast`, `findIndex`, `findLastIndex` | `find`, `find_last`, `find_index`, `find_last_index` with `predicate:` | Short-circuit search; reverse search visits from the end |
| `some`, `every` | `some(predicate:)`, `every(predicate:)` | Empty list produces false / true respectively |
| `filter`, `map`, `flatMap` | `filter(predicate:)`, `map(transform:)`, `flat_map(transform:)` | Map may change the element type; flat_map flattens one level |
| `flat` | imported `flatten(values:)` | One level of homogeneous nested lists; compose for deeper flattening |
| `reduce`, `reduceRight` | `fold(initial:, step:)`, `fold_right(initial:, step:)` | Always supply an initial accumulator; accumulator type may differ from element type |
| `forEach` | `for_each(operation:)` | Callback returns `Unit` |
| `reverse`, `toReversed` | `reverse()` | Returns a reversed copy |
| `sort`, `toSorted` | `sorted(compare:)` | Stable, explicit comparator returning negative / zero / positive `Int` |
| `slice` | `slice(start:, end:)` | Strict half-open bounds; faults for invalid bounds |
| `splice`, `toSpliced` | `with_values(start:, delete_count:, replacement:)` | Immutable replacement; start/count must describe a valid range |
| `with` | `with_value(index:, value:)` | Negative indexing supported; out-of-range update faults |
| `fill`, `copyWithin` | `fill(value:, start:, end:)`, `copy_within(target:, start:, end:)` | Immutable copies; strict bounds; overlap-safe copy truncates at the destination end |
| `keys`, `entries`, `values`, iteration | `keys()`, `entries()`, ordinary `for` over the list | Eager lists; entries are `ListEntry(index:, value:)` records |
| `join` | `List[String].join(separator:)` | Requires strings; formatting other types is explicit |
| `Array.of`, `Array.from` | bracket literals; `set.values()`, `map.entries()`, `text.scalar_values()` | Construction follows the source type, without dynamic array-like coercion |
| Repeated-value construction, numeric sequences | imported `filled(value:, count:, max_items:)`, `range(start:, end:, step:, max_items:)` | Bounded `Result`; range excludes end and accepts either step direction |
| `Map.groupBy`, `Object.groupBy` | `list.group_by(key:)`, imported `group_by(values:, key:)` | Hashable keys; first-seen group order and original order within each group |
| `new Set(array)` | `list.to_set()` | Requires `Hashable`; deduplicates in first-seen order |

Multi-parameter calls require argument labels; single-parameter methods and callbacks may omit the call label. Callback declarations retain their parameter names: `fn(value: T) -> U`, `fn(value: T) -> Bool`, or `fn(accumulator: A, value: T) -> A`. For an index-aware callback, use `list.entries()` and its typed `ListEntry` values. There is no implicit `this`, sparse slot, callback arity coercion, default comparator, or heterogeneous list.

Native methods introduce only their own output/accumulator variables. Inference uses supplied arguments rather than the surrounding expected result. Specialize a generic method when saving it as a value:

```manuscript
import panic from "@std/faults.ms"

import List from "@std/collections.ms"

fn label(value: Int) -> String:
    return "item {value}"

test "receiver methods compose":
    let labels = [1, 2].map(transform: label)
    if not (labels.join(separator: ", ") == "item 1, item 2"):
        return panic(message: "check failed")
    let convert = [3, 4].map[String]
    if not (convert(transform: label) == ["item 3", "item 4"]):
        return panic(message: "check failed")
```

Generic operations in these pinned native declarations do not add generic operation syntax to application-defined interfaces or implementations.

## Map and Set

Import `Map` / `Set` when naming or constructing them. Keys and set elements satisfy `Hashable`. Enumeration returns immutable lists in insertion order. Collection equality is independent of insertion order.

| JavaScript surface | Manuscript equivalent | Contract |
| --- | --- | --- |
| `Map.size`, `get`, `has`, `set`, `delete` | `length`, `get`, `contains`, `with_entry`, `without` | Existing immutable receiver methods; missing lookup is `Optional` |
| `Map.clear`, `keys`, `values`, `entries`, `forEach` | `clear`, `keys`, `values`, `entries`, `for_each` | Entries are `MapEntry(key:, value:)`; callback is `fn(key: K, value: V) -> Unit` |
| `Map.getOrInsert` | `with_default(key:, value:)` followed by `get(key:)` | Returns the updated map; an existing value is preserved |
| `Map.getOrInsertComputed` | `with_default_from(key:, create:)` followed by `get(key:)` | Callback receives `key:` and runs exactly once if absent |
| `new Map(entries)`, `Object.fromEntries` | imported `map_from_entries(entries:)` | Duplicate keys keep first insertion position and use last value |
| Map/object merging | `map.merge(other:)` | Right values replace matching entries in place; new keys append |
| `Set.size`, `has`, `add`, `delete` | `length`, `contains`, `with_value`, `without` | Existing immutable receiver methods |
| `Set.clear`, `values`, `keys`, `entries`, `forEach` | `clear`, `values`, `values`, `entries`, `for_each` | Set keys and values share one spelling; entries contain `[value, value]` |
| `union`, `intersection`, `difference`, `symmetricDifference` | `union(right:)`, `intersection(right:)`, `difference(right:)`, `symmetric_difference(right:)` | New sets; left traversal order, then right-only values where applicable |
| `isSubsetOf`, `isSupersetOf`, `isDisjointFrom` | `is_subset_of(right:)`, `is_superset_of(right:)`, `is_disjoint_from(right:)` | Boolean relations; arguments are typed sets |

Use `Map[String, T]` for a dynamic string-keyed object. Statically declared records retain named fields and nominal identities. Prototype lookup, property descriptors, dynamic record reflection, `WeakMap`, `WeakSet`, and finalization registries have no corresponding data API.

## String

String methods need no additional import. The same algorithms are available as individually imported `@std/string.ms` functions. Strings are valid UTF-8; indexes and lengths below count Unicode scalars, not JavaScript UTF-16 code units or user-perceived graphemes.

| JavaScript surface | Manuscript equivalent | Contract |
| --- | --- | --- |
| `length`, `at`, `charAt`, `charCodeAt`, `codePointAt` | `scalar_length()`, `at(index:)`, `scalar_at(index:)` | Scalar text / scalar integer in `Optional`; negative indexes count from end |
| `includes`, `startsWith`, `endsWith` | `contains(text:)`, `starts_with(prefix:)`, `ends_with(suffix:)` | Literal substring operations |
| `indexOf`, `lastIndexOf` | `index_of(value:)`, `last_index_of(value:)` | Scalar index in `Optional`; empty search finds start / end |
| `slice`, `substring` | `slice(start:, end:)`, `substring(start:, end:)` | Slice clamps relative bounds; substring clamps nonnegative bounds and swaps reversed endpoints |
| Strict scalar extraction | `slice_scalars(start:, end:)` | Existing `Result` returning `OutOfRange` for invalid bounds |
| `split` | `split(separator:, max_parts:)` | Positive maximum; final part retains the remainder; empty separator splits scalars |
| `concat` | `concat(values:)`, interpolation | Concatenates text explicitly |
| `trim`, `trimStart`, `trimEnd` | `trim()`, `trim_start()`, `trim_end()` | Unicode whitespace |
| `toLowerCase`, `toUpperCase` | `lower()`, `upper()` | Go Unicode simple case mapping; not locale-sensitive full case expansion |
| `repeat` | `repeat(count:, max_bytes:)` | Existing bounded `Result` |
| `replace` | `replace(old:, new:, max_replacements:)` | Literal replacement; zero replacements preserves text; empty old inserts at scalar boundaries |
| `replaceAll` | `replace_all(old:, new:, max_bytes:)` | Literal replacement, including empty old; output limit checked before each append |
| `padStart`, `padEnd` | `pad_start(target_length:, padding:, max_bytes:)`, `pad_end(...)` | Scalar length, complete scalar truncation of padding, bounded output; empty padding preserves text |
| `normalize` | `normalize(form:, max_bytes:)` | NFC, NFD, NFKC, NFKD; bounded output, Unicode stream-safe handling of long combining runs |
| `String.fromCodePoint` | imported `from_scalars(values:)` | Rejects surrogates and invalid scalar values |
| `match`, `matchAll`, `search`, regexp replacement | `Regex.matches`, `find_all`, `replace`; imported regex functions | RE2-style patterns; explicit match/output limits; captured-group/index records remain a gap |
| UTF-8 conversion | `to_bytes()`, `Bytes.to_text()` | Invalid UTF-8 decoding yields `none` |

Locale collation/case mapping (`localeCompare`, locale case methods, `Intl`), grapheme segmentation, capture-rich regex results, and search start-position options remain gaps. Manuscript valid UTF-8 makes lone-surrogate repair (`isWellFormed` / `toWellFormed`) unnecessary. Legacy `substr` and HTML wrapper methods are intentionally omitted.

## Other built-ins

| JavaScript facility | Manuscript option | Coverage / difference |
| --- | --- | --- |
| Number string formatting | `Int.to_string(radix:)`, `Float.to_string()`, `to_fixed(digits:)`, `to_exponential(digits:)`, `to_precision(precision:)` | Precision methods return `Result`, permit 0–100 fraction digits / 1–100 significant digits, retain signed zero, and round ties to even |
| Number predicates / parsing | `Float.is_nan()`, `is_finite()`, imported strict number parsers; `truncate_to_int()` | No partial parsing or silent coercion; isInteger can compare truncation or use `@std/math.ms` |
| BigInt | Imported constructor/parser and `add`, `subtract`, `multiply`, `divide`, `remainder`, `compare`, bit methods, `to_int`, `to_string` receivers | Division errors are values; integer exponent/shift operations remain gaps |
| Typed byte array / Buffer | `Bytes` with `at`, `get`, `contains`, `index_of`, `last_index_of`, prefix/suffix tests, `slice`, `reverse`, `with_value`, `concat` | Immutable byte storage; imported binary functions provide signed/unsigned integer and Float reads/writes |
| Math | `@std/math.ms` | Existing elementary math, trigonometry, rounding, constants; random authority is explicit |
| JSON | `@std/json.ms` | Existing parse/stringify with exact decimal number text and explicit limits |
| Promise aggregation | ordinary suspending functions; `parallel`, `parallel_map`, `Background` | Joined work and lexical cleanup; no detached Promise or microtask compatibility |
| Date / timers | `@std/time.ms`, explicit Clock / WallClock capabilities | Timestamp parse/format, shifts/differences, monotonic timers; calendar/timezone/locale formatting remains a gap |
| ArrayBuffer / DataView | `Bytes`, `@std/binary.ms` | No shared raw memory, typed numeric views, or Atomics; use Synchronized / Queue |
| Object / Reflect / Proxy / Symbol | Records, alternatives, maps, explicit contracts | Dynamic prototypes, property traps, metaprogramming, boxed primitive methods, and VM reflection are outside the typed data API |

See [Node.js and Go coverage](coverage.md) for files, networking, streams, crypto, processes, compression, and other application facilities already present. The table records functional breadth without claiming JavaScript source or runtime compatibility.
