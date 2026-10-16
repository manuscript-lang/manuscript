# Canonical standard-library declarations. Implementations are native.

# Errors returned when a collection factory exceeds its supplied item limit.
export type CollectionError:
    # A count, item budget, or step is invalid: `count` or `max_items` is negative, or `range` has a zero `step`.
    case InvalidInput
    # The result would hold more items than `max_items`, or more than the runtime's ceiling of 268435456 (2^28) items when `max_items` is omitted.
    case LimitExceeded
    # A slice bound lies outside 0 <= start <= end <= length after negative bounds are resolved from the end.
    case OutOfRange

# An ordered mutable collection with indexing, iteration, and transformations.
# Primitive backing stores Int and Float values at 64 bits, Bool values as bytes, and String references without an element box.
# Generic forwarding retains the same List identity; clone and slice copy outer storage.
export type List[T]:
    # Returns a shallow copy with independent list storage.
    fn clone() -> List[T]:
    # Returns an element; negative indexes are relative to the end, and out-of-range indexes return none.
    fn at(index: Int) -> Optional[T]:
    # Reports whether any element equals `value`, using the element type's Equal implementation; an empty list returns false.
    fn contains(value: T) -> Bool:
    # Returns the first equal element's zero-based index, or none; elements require Equal.
    fn index_of(value: T) -> Optional[Int]:
    # Returns the last equal element's zero-based index, or none; elements require Equal.
    fn last_index_of(value: T) -> Optional[Int]:
    # Returns the first element, or none when the list is empty.
    get first -> Optional[T]:
    # Returns the last element, or none when the list is empty.
    get last -> Optional[T]:
    # Reports whether the list has no elements.
    get is_empty -> Bool:
    # Inserts `value` at index 0 in place, shifting existing elements one position later, and returns this same list.
    fn prepend(value: T) -> List[T]:
    # Inserts value before index in place and returns this list; negative indexes count from the end.
    # Requires -length <= index <= length; index length appends, and invalid indexes fault.
    fn insert(index: Int, value: T) -> List[T]:
    # Removes and returns the last element in place, or none for an empty list.
    fn pop() -> Optional[T]:
    # Replaces an element in place and returns this list; negative indexes count from the end.
    # Invalid indexes fault.
    fn set(index: Int, value: T) -> List[T]:
    # Removes an element in place and returns this list; negative indexes count from the end.
    # Invalid indexes fault.
    # Shifts the suffix without clearing prior values retained in spare backing capacity.
    fn remove(index: Int) -> List[T]:
    # Returns a new shallow List containing [start, end); outer storage is independent.
    # Negative bounds are relative to the end; bounds outside 0 <= start <= end <= length return CollectionError.OutOfRange.
    fn slice(start: Int, end: Int) -> Result[List[T], CollectionError]:
    # Copies the first min(count, length) elements into fresh shallow List storage.
    # Leaves the receiver unchanged; negative count is a programming fault.
    fn take(count: Int) -> List[T]:
    # Copies the remainder after min(count, length) into fresh shallow List storage.
    # Leaves the receiver unchanged; negative count is a programming fault.
    fn drop(count: Int) -> List[T]:
    # Reverses this list in place and returns the same instance.
    fn reverse_in_place() -> List[T]:
    # Returns a reversed shallow copy with independent outer storage; nested references remain shared.
    fn reversed() -> List[T]:
    # Returns a new list sorted by negative/zero/positive comparator results.
    fn sorted(compare: fn(left: T, right: T) -> Int) -> List[T]:
    # Keeps matching values in their original order.
    fn filter(predicate: fn(value: T) -> Bool) -> List[T]:
    # Returns the first element for which `predicate` is true, or none; later elements are not tested after a match.
    fn find(predicate: fn(value: T) -> Bool) -> Optional[T]:
    # Searches from the end and returns the last element for which `predicate` is true, or none.
    fn find_last(predicate: fn(value: T) -> Bool) -> Optional[T]:
    # Returns the zero-based index of the first element for which `predicate` is true, or none.
    fn find_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
    # Searches from the end and returns the last matching zero-based index, or none.
    fn find_last_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
    # Counts values satisfying the predicate, calling it once per element in order.
    fn count(predicate: fn(value: T) -> Bool) -> Int:
    # Returns a new shallow List keeping each first equal element in order; elements require Equal.
    fn distinct() -> List[T]:
    # Returns true when at least one value satisfies the predicate.
    fn some(predicate: fn(value: T) -> Bool) -> Bool:
    # Returns true when every value satisfies the predicate; empty lists return true.
    fn every(predicate: fn(value: T) -> Bool) -> Bool:
    # Calls operation(value:) over the initial backing slice and length; element writes can affect later calls, and append does not extend traversal.
    fn for_each(operation: fn(value: T) -> Unit) -> Unit:
    # Calls `key` once per element in order and returns a map from each distinct key to the elements that produced it.
    # Keys appear in first-seen order and each group keeps the original element order.
    fn group_by[K: Hashable](key: fn(value: T) -> K) -> Map[K, List[T]]:
    # Returns a new list holding `transform` applied to each element in order; the receiver is unchanged.
    fn map[U](transform: fn(value: T) -> U) -> List[U]:
    # Calls `transform` on each element in order and concatenates the returned lists into one new list; the receiver is unchanged.
    fn flat_map[U](transform: fn(value: T) -> List[U]) -> List[U]:
    # Reduces values from left to right, starting with `initial`.
    fn fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    # Reduces values from right to left, starting with `initial`.
    fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    # Replaces delete_count elements starting at start, mutating and returning this List.
    # Requires 0 <= start <= length and 0 <= delete_count <= length - start; invalid bounds fault without clamping.
    # Replacement references stay shallow; using this same List as replacement stages its prior values.
    # Shrinking retains prior values in spare backing capacity, following captured Go slice traversal.
    fn splice(start: Int, delete_count: Int, replacement: List[T]) -> List[T]:
    # Sets elements in [start, end) to `value` in place and returns this list.
    # Bounds must satisfy 0 <= start <= end <= length; negative or larger bounds fault rather than counting from the end, and an empty range changes nothing.
    fn fill(value: T, start: Int, end: Int) -> List[T]:
    # Copies the elements in [start, end) to begin at index `target`, in place, and returns this list.
    # The list never grows: copying stops at the end of the list. Source bounds must satisfy 0 <= start <= end <= length and a target must be within 0 through length; otherwise the call faults.
    fn copy_within(target: Int, start: Int, end: Int) -> List[T]:
    # Returns a new set of the distinct elements, using Hashable equality; the first of equal elements is kept in insertion order.
    fn to_set() -> Set[T]:
    # Returns a new list of the zero-based indexes 0 through length - 1.
    fn keys() -> List[Int]:
    # Returns a new list of `ListEntry` records pairing each zero-based index with its element, in order.
    fn entries() -> List[ListEntry[T]]:
    # Concatenates the strings with `separator` between neighbors; an empty list returns an empty string.
    # Available only on List[String].
    fn join(separator: String) -> String:
    # Adds `value` at the end in place and returns this same list.
    fn append(value: T) -> List[T]:
    # Returns a new list holding this list's elements followed by `other`; neither operand is changed.
    fn concat(other: List[T]) -> List[T]:
    # Returns the number of elements.
    get length -> Int:

# A mutable key-value collection. Keys use explicit `Hashable` value semantics.
export type Map[T: Hashable, U]:
    # Returns a shallow copy with independent map storage.
    fn clone() -> Map[T, U]:
    # Reports whether this map has no entries.
    get is_empty -> Bool:
    # Copies matching entries in insertion order, retaining payload references.
    # Callbacks traverse a snapshot even when they mutate the receiver.
    fn filter(predicate: fn(key: T, value: U) -> Bool) -> Map[T, U]:
    # Transforms values in snapshot insertion order, retaining original keys.
    # Returns independent outer storage with shallow key and result references.
    fn map[W](transform: fn(key: T, value: U) -> W) -> Map[T, W]:
    # Transforms keys in snapshot insertion order, retaining value references.
    # Equal outputs keep the first key/position and the last input value.
    fn map_keys[W: Hashable](transform: fn(key: T, value: U) -> W) -> Map[W, U]:
    # Returns the stored value or an eagerly evaluated fallback without inserting.
    fn get_or(key: T, fallback: U) -> U:
    # Reduces an entry snapshot in insertion order, starting with initial.
    fn fold[A](initial: A, step: fn(accumulator: A, key: T, value: U) -> A) -> A:
    # Reduces an entry snapshot in reverse insertion order, starting with initial.
    fn fold_right[A](initial: A, step: fn(accumulator: A, key: T, value: U) -> A) -> A:
    # Returns the first matching entry as a fresh record with shallow references.
    fn find(predicate: fn(key: T, value: U) -> Bool) -> Optional[MapEntry[T, U]]:
    # Searches a snapshot from the end, stopping at the last matching entry.
    # Returns a fresh entry record retaining its original key/value references.
    fn find_last(predicate: fn(key: T, value: U) -> Bool) -> Optional[MapEntry[T, U]]:
    # Stops at the first matching entry; empty maps return false.
    fn some(predicate: fn(key: T, value: U) -> Bool) -> Bool:
    # Stops at the first nonmatching entry; empty maps return true.
    fn every(predicate: fn(key: T, value: U) -> Bool) -> Bool:
    # Inserts a default only when the key is absent and returns this map.
    # The supplied value evaluates normally even when the key already exists.
    fn add_default(key: T, value: U) -> Map[T, U]:
    # Creates and inserts a default only when the key is absent, then returns this map.
    # Calls create(key:) once for absence; an existing key leaves its value and position unchanged.
    fn add_default_from(key: T, create: fn(key: T) -> U) -> Map[T, U]:
    # Removes every entry in place and returns this same map; aliases observe the empty map.
    fn clear() -> Map[T, U]:
    # Returns a new list of the keys in insertion order.
    fn keys() -> List[T]:
    # Returns a new list of the values in insertion order.
    fn values() -> List[U]:
    # Returns a new list of fresh `MapEntry` records in insertion order; keys and values keep their original references.
    fn entries() -> List[MapEntry[T, U]]:
    # Copies every entry of `other` into this map in place and returns this map.
    # Existing keys keep their position and key but take the value from `other`; new keys append in `other` order. `other` is unchanged.
    fn merge(other: Map[T, U]) -> Map[T, U]:
    # Calls operation(key:, value:) sequentially over an insertion-order membership snapshot.
    fn for_each(operation: fn(key: T, value: U) -> Unit) -> Unit:
    # Reports whether an equal key is present, using the key type's Hashable implementation.
    fn contains(key: T) -> Bool:
    # Returns the value stored for an equal key, or none when the key is absent.
    fn get(key: T) -> Optional[U]:
    # Returns the number of entries.
    get length -> Int:
    # Inserts or replaces a value and returns this map; replacement keeps the original key and insertion position.
    fn add(key: T, value: U) -> Map[T, U]:
    # Removes an equal key and returns this same Map; remaining entries retain insertion order.
    # An absent key leaves values and ordering unchanged; lookup uses the selected Equal/Hashable scope.
    fn remove(key: T) -> Map[T, U]:

# One key-value pair returned by `Map.entries`.
export type MapEntry[T: Hashable, U]:
    # The lookup identity of the pair; unique within its map under Hashable equality.
    key: T
    # The payload stored for `key`; the reference is shared with the map, not copied.
    value: U

# A mutable collection of unique values using explicit `Hashable` value semantics.
export type Set[T: Hashable]:
    # Copies outer storage, retaining element references and insertion order.
    fn clone() -> Set[T]:
    # Reports whether this set has no elements.
    get is_empty -> Bool:
    # Copies matching elements in insertion order, retaining payload references.
    # Callbacks traverse a snapshot even when they mutate the receiver.
    fn filter(predicate: fn(value: T) -> Bool) -> Set[T]:
    # Transforms a snapshot into a fresh set, retaining the first equal result.
    fn map[U: Hashable](transform: fn(value: T) -> U) -> Set[U]:
    # Reduces an element snapshot in insertion order, starting with initial.
    fn fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    # Reduces an element snapshot in reverse insertion order, starting with initial.
    fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    # Returns the original first matching element, or none.
    fn find(predicate: fn(value: T) -> Bool) -> Optional[T]:
    # Searches a snapshot from the end, returning the original last matching element.
    fn find_last(predicate: fn(value: T) -> Bool) -> Optional[T]:
    # Stops at the first matching element; empty sets return false.
    fn some(predicate: fn(value: T) -> Bool) -> Bool:
    # Stops at the first nonmatching element; empty sets return true.
    fn every(predicate: fn(value: T) -> Bool) -> Bool:
    # Returns a new set with receiver values followed by right-only values in insertion order.
    fn union(other: Set[T]) -> Set[T]:
    # Returns a new set of receiver values also in right, preserving receiver insertion order.
    fn intersection(other: Set[T]) -> Set[T]:
    # Returns a new set of receiver values absent from right, preserving receiver insertion order.
    fn difference(other: Set[T]) -> Set[T]:
    # Returns a new set of values in exactly one operand; leaves both operands unchanged.
    fn symmetric_difference(other: Set[T]) -> Set[T]:
    # Tests whether every receiver value also occurs in right.
    fn is_subset_of(other: Set[T]) -> Bool:
    # Tests whether every right value also occurs in the receiver.
    fn is_superset_of(other: Set[T]) -> Bool:
    # Tests whether the operands have no common values.
    fn is_disjoint_from(other: Set[T]) -> Bool:
    # Removes all values in place and returns this set; aliases observe the empty set.
    fn clear() -> Set[T]:
    # Returns a shallow list of values in insertion order.
    fn values() -> List[T]:
    # Returns a new list of [value, value] lists in insertion order.
    fn entries() -> List[List[T]]:
    # Calls operation(value:) sequentially over an insertion-order membership snapshot.
    fn for_each(operation: fn(value: T) -> Unit) -> Unit:
    # Reports whether an equal value is present, using the element's Hashable implementation.
    fn contains(value: T) -> Bool:
    # Returns the number of distinct values currently stored.
    get length -> Int:
    # Adds a value in place and returns this set; an equal value retains its original payload and position.
    fn add(value: T) -> Set[T]:
    # Removes an equal value in place and returns this set; an absent value leaves it unchanged.
    fn remove(value: T) -> Set[T]:

# One list index and its corresponding value.
export type ListEntry[T]:
    # Zero-based position of the element in the list that produced this entry.
    index: Int
    # The element found at `index`.
    value: T

# Creates a list containing `value` repeated `count` times.
export fn filled[T](
    value: T,
    count: Int,
    max_items: Optional[Int] = none
) -> Result[List[T], CollectionError]:

# Creates integers from `start` up to but excluding `end` using `step`.
export fn range(
    start: Int,
    end: Int,
    step: Int,
    max_items: Optional[Int] = none
) -> Result[List[Int], CollectionError]:

# Builds a map from entries. Later entries replace earlier values for duplicate keys.
export fn map_from_entries[K: Hashable, V](entries: List[MapEntry[K, V]]) -> Map[K, V]:

impl Error for CollectionError:
    # Returns the fixed diagnostic `collection: <reason>`, such as `collection: limit exceeded`, without echoing values.
    fn message() -> String:

# Appends values efficiently before freezing them into a list.
export type ListBuilder[T]:
    # Adds `value` to the end of the shared builder and returns Unit.
    # A frozen builder faults.
    fn append(value: T) -> Unit:
    # Seals the builder and returns the accumulated list without copying it.
    # Later `append` calls fault.
    fn freeze() -> List[T]:

# Adds entries efficiently before freezing them into a map.
export type MapBuilder[T: Hashable, U]:
    # Seals the builder and returns the accumulated map without copying it.
    # Later `add` calls fault.
    fn freeze() -> Map[T, U]:
    # Inserts or replaces an entry in the shared builder; returns Unit like all builder mutations.
    # Replacement retains the original key and insertion position; a sealed builder faults.
    fn add(key: T, value: U) -> Unit:

# Adds unique values efficiently before freezing them into a set.
export type SetBuilder[T: Hashable]:
    # Seals the builder and returns the accumulated set without copying it.
    # Later `add` calls fault.
    fn freeze() -> Set[T]:
    # Adds a value to the shared builder; returns Unit like all builder mutations.
    # Equal values retain the first payload and position; a sealed builder faults.
    fn add(value: T) -> Unit:

# documentation documentation/standard-library/builders.md
# +++
# title = "Building values"
# weight = 6
# +++
#
# # Building values
#
# Ordinary collections already support mutation. Use a builder when construction needs synchronized access and an atomic sealed result. A builder returns its result when sealed. Builder aliases are ordinary references; freezing may seal the builder so later mutation reports a runtime error.
#
# Builders synchronize mutation and freeze across all aliases. Freezing seals the object atomically; an append racing with freeze either contributes to the snapshot or faults after sealing. Concurrent appends have nondeterministic order. There is no ownership-transfer or consuming function type.
#
# ## API
#
# Collection builders are exported by `@std/collections.ms`; BytesBuilder by `@std/bytes.ms`; StringBuilder by `@std/string.ms`. They have zero-argument constructors and are opaque references with no equality or hashing. Type arguments can come from an explicit application or a complete expected constructor type.
#
# | Type | Mutation | Freeze result |
# | --- | --- | --- |
# | `ListBuilder[T]` | `append(value: T) -> Unit` | `List[T]` |
# | `MapBuilder[K: Hashable, V]` | `add(key: K, value: V) -> Unit` | `Map[K, V]` |
# | `SetBuilder[T: Hashable]` | `add(value: T) -> Unit` | `Set[T]` |
# | `BytesBuilder` | `append(value: Int) -> Unit`, `concat(values: Bytes) -> Unit` | `Bytes` |
# | `StringBuilder` | `append(value: String) -> Unit` | `String` |
#
# All builder mutations return `Unit`; they update the builder through its existing reference. Ordinary collection mutators return their collection for chaining; builders return their constructed value only from `freeze`. See the [migration table](../core-language/types/collections.md#naming-and-migration).
#
# `freeze()` seals the shared local object and returns its result. Repeated freeze returns the same value. List, Map, and Set results are ordinary mutable collections; sealing prevents further builder operations, not mutation through the result. Use `.clone()` to retain a separate copy. Every builder mutation through any alias after sealing is a programming fault. Byte append requires 0 through 255. Map replacement preserves insertion position; set insertion ignores an already present value. Builders have no implicit cleanup or ownership transfer.
#
# See [references inside other values](../core-language/types/references.md) and [collections](../core-language/types/collections.md).
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import MapBuilder from "@std/collections.ms"
# import panic from "@std/faults.ms"
#
# test "build entries with a stored Unit operation":
#     let builder = MapBuilder[String, Int]()
#     let add: fn(key: String, value: Int) -> Unit = builder.add
#     add("a", 1)
#     add("a", 2)
#     let result = builder.freeze()
#     if result.get("a") != some(2): return panic("builder replacement")
# ```
# end-documentation

# documentation documentation/standard-library/data.md
# +++
# title = "Text and collections"
# weight = 5
# +++
#
# # Text and collections
#
# Use receiver operations for existing data: `text.split(separator: ",")`, `bytes.slice(start: 0, end: 4)` (a `Result`), `values.map(transform: transform)`, and `left.union(right)`. Standalone functions create or decode values, such as `from_scalars`, `filled`, `range`, `map_from_entries`, and `compile` for a regular expression.
#
# | Group | Source module | Reference |
# | --- | --- | --- |
# | String operations and StringBuilder | `@std/string.ms` | [Text](reference/string.md) |
# | Bytes operations and BytesBuilder | `@std/bytes.ms` | [Bytes](reference/bytes.md) |
# | List, Map, Set and their builders | `@std/collections.ms` | [Collections](reference/collections.md) |
# | Local FIFO and priority queues | `@std/queues.ms` | [Queue contracts](../concurrency/queues.md) |
# | Equality and hashing interfaces | `@std/equality.ms` | [Equality rules](../core-language/types/equality-and-hashing.md) |
# | Base64 and hexadecimal encoding | `@std/encoding.ms` | [Encodings](reference/encoding.md) |
# | Binary numbers | `@std/binary.ms` | [Binary](reference/binary.md) |
# | Regular expressions | `@std/regex.ms` | [Regex](reference/regex.md) |
#
# List, Map and Set mutation is visible through aliases. `.clone()` makes a separate shallow copy. `sorted` returns a new list and accepts a comparator; there are no separate integer and string sorting helpers. Flatten a nested list with `flat_map` and an identity callback. Use `.at` for optional indexed access, including relative negative indexes on List and Bytes.
#
# ## Transform and search lists
#
# `take(count:)` returns a shallow copy of the first `count` elements; `drop(count:)` returns a shallow copy after them. Counts above `length` are clamped: taking copies the whole list, dropping returns an empty list. Zero takes an empty list or drops nothing; a negative count produces a programming fault naming the operation, parameter and original count. Both return fresh mutable List storage even for empty or whole-list copies, preserve element order and payload references, and leave the receiver unchanged. They are explicit copy operations and do not change loop or callback traversal behavior.
#
# `count(predicate:)` returns how many elements match, and `distinct()` returns a new shallow list keeping the first of each group of equal elements in their original order; like `contains`, it requires `Equal` elements and compares each element with those already kept. `insert(index:, value:)` and `pop()` mutate the receiver: `insert` accepts `-length` through `length` and returns the same list, while `pop` removes the last element and returns it, or `none` for an empty list.
#
# `map` transforms each element, `filter` keeps matching elements, and `flat_map` combines the lists returned by its callback. These operations return new lists. Callbacks run sequentially and may wait for operations.
#
# Inside a function or test:
#
# ```manuscript
# let labels = [1, 2].map(transform: fn(value: Int) -> String:
#     return "item {value}"
# )
# let line = labels.join(separator: ", ")
# # line is "item 1, item 2".
# ```
#
# `List`, `Map`, and `Set` are available without imports. `find` and `find_index` stop at the first match and return an `Optional`; `find_last` and `find_last_index` search from the end. `index_of` and `last_index_of` search by equality. `for_each` runs a sequential callback and returns Unit. `some` and `every` return a `Bool`; an empty list produces false and true respectively. `fold` and `fold_right` require an initial accumulator, which may have a different type from the elements. Sorting is stable and requires an explicit comparator. See [search and enumeration](../core-language/types/collections.md#search-and-enumeration) for callback labels, entry shapes, and Set relation operations.
#
# ## Map and set order
#
# Maps and sets enumerate in insertion order, while equality ignores order. Replacing an existing map key retains its position; removing and adding it puts it at the end. `map_from_entries` uses the last value for duplicate keys and keeps the first insertion position. `merge` mutates the receiving map, replacing matching values and appending new keys.
#
# `add_default_from` calls its creation function only when the key is absent. Set algebra returns new sets: left-side traversal order is retained, followed by right-only values where applicable. Keys and set elements must satisfy [Hashable](../core-language/types/equality-and-hashing.md).
#
# ## Text and regular expressions
#
# String indexing and search count Unicode scalars. The [text rules](../core-language/basics/text-and-bytes.md#indexing-and-character-boundaries) specify units and the relative negative and strict slice bounds. String operations return new text and leave the receiver unchanged.
#
# | String operations | Behavior |
# | --- | --- |
# | `contains`, `starts_with`, `ends_with` | Test exact text contents without normalization. |
# | `trim`, `trim_start`, `trim_end` | Remove Unicode whitespace from both ends, the start, or the end. Whitespace is U+0009–U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, and U+3000. |
# | `upper`, `lower` | Apply locale-independent full Unicode case mapping; the scalar length can change. |
# | `scalar_length`, `scalar_values` | Count Unicode scalars or return their integer code points. |
# | `length`, `is_empty`, `chars`, `reverse` | Count/test text, collect one String per scalar, or reverse scalar order; returned lists have fresh storage. |
# | `compare` | Return -1/0/1 in case-sensitive lexical scalar order without locale or normalization. |
# | `lines` | Split LF/CRLF terminators, retaining interior empty lines and standalone CR; omit an extra trailing item. See the exact [text rules](../core-language/basics/text-and-bytes.md#indexing-and-character-boundaries). |
# | `pad_start`, `pad_end` | Repeat and truncate `padding` on scalar boundaries until `target_length` scalars are reached. A shorter target or empty padding leaves the text unchanged. Negative targets return `InvalidInput`. |
# | `replace_first` | Replace the first occurrence by default (omitted or `none` cap); a supplied `max_replacements` can replace more than one occurrence, and zero leaves text unchanged. Negative caps fault. `replace` remains a compatible spelling with identical defaults, caps, and faults. |
# | `replace_n` | Replace at most the required `max_replacements: Int` nonoverlapping literal occurrences. Zero leaves text unchanged; negative counts retain replace's programming fault. This count is not a UTF-8 byte budget. |
# | `replace_all` | Replace every nonoverlapping occurrence. Return `StringError.LimitExceeded` if the UTF-8 output exceeds a supplied `max_bytes`, or `InvalidInput` for a negative budget. |
# | `split` | Split on exact separators and truncate to a supplied `max_parts`; zero returns no parts and negative limits fault. Empty text split on a nonempty separator returns `[""]`; an empty separator splits into scalars, giving no parts for empty text. |
#
# For a finite cap, use `text.replace_n(old: "a", new: "b", max_replacements: 2)`. Current `replace_first` is a transitional compatibility spelling: its retained count parameter can replace more than one match. Its signature remains supported; a future strict first-only shape requires a separate reviewed migration. `replace_n` has no additional output-byte/allocation budget, and replacement text can grow the result; `replace_all` provides a separate byte-budgeted operation.
#
# An empty `old` in `replace_first` (or `replace`), `replace_n` and `replace_all` matches before the first scalar and after each scalar, including the end. Replacement does not scan newly inserted text. `repeat`, `normalize`, `pad_start`, and `pad_end` also accept optional UTF-8 output budgets: omitted or `none` budgets impose no cap, zero permits only empty output, negatives return `StringError.InvalidInput`, and exceeding a supplied budget returns `StringError.LimitExceeded`. Even unchanged padding results must fit the supplied budget. Normalization accepts exactly the case-sensitive strings `NFC`, `NFD`, `NFKC`, or `NFKD`; other forms return `StringError.InvalidInput`.
#
# Use `NormalizationForm.Nfc`, `Nfd`, `Nfkc`, or `Nfkd` from `@std/string.ms` to select a form with a checked alternative. Its `normalize(text, max_bytes = none)` operation shares the existing String implementation, UTF-8 byte budgets, errors, and cancellation. Canonical forms compose/decompose canonically equivalent text; compatibility forms also normalize compatibility characters such as ligatures.
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import NormalizationForm from "@std/string.ms"
# import panic from "@std/faults.ms"
#
# test "typed Unicode normalization":
#     let text = NormalizationForm.Nfkc.normalize("ﬁ", max_bytes: 2).unwrap()
#     if text != "fi": return panic("compatibility normalization")
# ```
#
# Negative `max_parts` and `max_replacements` fault with a message naming the operation and parameter, because these operations return plain values. Full case mapping includes `"ß".upper()` as `"SS"`, `"ﬁ".upper()` as `"FI"`, final sigma `ς` at the end of `"ΑΣ".lower()`, and `"İ".lower()` as `i` followed by U+0307.
#
# Regex uses RE2 syntax. Backreferences and lookbehind are unsupported; malformed patterns return typed errors. See [common contracts](contracts.md) for optional budgets and the [API reference](reference/_index.md) for exact signatures.
#
# `Regex.replace_all(text:, replacement:, max_bytes:)` replaces every nonoverlapping match with literal text; `$1` does not expand a capture. Omitted or `none` byte budgets impose no cap, zero permits only empty output, negative budgets return `RegexError.InvalidInput`, and output exceeding a supplied budget returns `RegexError.LimitExceeded`. The UTF-8 budget includes unmatched input, even when no match occurs.
#
# ## Byte operations
#
# | Bytes operations | Behavior |
# | --- | --- |
# | `length`, `is_empty`, `at` | Count bytes, test emptiness, or read an unsigned byte; negative lookup indexes are relative to the end. |
# | `contains`, `starts_with`, `ends_with` | Test byte subsequences, prefixes, or suffixes. |
# | `index_of`, `last_index_of` | Return the first or last matching byte offset, or `none`; empty searches match at zero or `length` respectively. |
# | `split` | Split exact binary separators into a fresh List of immutable Bytes views. `max_parts` truncates returned parts; omitted/`none` is unlimited, zero returns no parts, negatives fault. |
# | `slice` | Select a half-open byte range, returning `OutOfRange` for invalid bounds, under the [slice rules](../core-language/basics/text-and-bytes.md#half-open-slices). |
# | `with_value`, `reversed`, `concat`, `clone` | Return Bytes without changing the receiver. `with_value` accepts relative negative indexes; an invalid index or a value outside 0–255 faults. |
# | `values` | Return a fresh mutable `List[Int]` of bytes; `values(data:)` remains available as a free function. |
# | `to_text` | Decode valid UTF-8 or return `none`. |
#
# Bytes stay immutable even when a native slice shares storage. Construction and extraction copy values, as described in [encoding and parsing](../core-language/basics/text-and-bytes.md#encoding-and-parsing).
#
# `Bytes.split` preserves leading, interior and trailing empty parts. An empty separator yields one Bytes per byte, and gives no parts for empty data; a nonempty separator gives one empty part for empty data. It never decodes UTF-8, so separators can split a multibyte character or invalid text. A cap discards later parts instead of retaining an unsplit remainder: `Bytes([1, 0, 2, 0, 3]).split(Bytes([0]), max_parts: 2)` returns `[Bytes([1]), Bytes([2])]`. Returned Lists have independent mutable storage, while their immutable Bytes may share the input storage. Changing a result with `with_value` creates new Bytes and leaves the input and other parts unchanged.
#
# ## Base64 encoding
#
# `base64_encode(data: bytes)` and `base64_decode(text: "/w==")` use the standard alphabet by default. Pass `url_safe: true` for the URL-safe alphabet (`_w==` for the same byte). Decoding still validates the selected alphabet and an explicit `max_bytes` output budget; zero is a supplied budget.
# end-documentation
