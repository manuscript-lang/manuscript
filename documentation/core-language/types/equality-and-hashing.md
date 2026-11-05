+++
title = "Equality and hashing"
weight = 8
+++

# Equality and hashing

Suppose a contact list contains the same address twice. Comparing addresses tells you whether two entries name the same recipient. A set uses that equality to keep one entry per recipient; a map uses it to find the value associated with a key. Hashing helps those lookups find a candidate quickly, then equality decides whether it is the right key.

## Find an entry and remove duplicates

Save this complete program as `recipients.ms` and run `ms run recipients.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"2 recipients\n2 deliveries\n0 deliveries\n","filename":"recipients.ms"} -->
```manuscript
export fn main() Int:
    let addresses = ["ada@example.com", "lin@example.com", "ada@example.com"]
    let recipients = Set(addresses)
    print("{recipients.length()} recipients")

    let delivered = {"ada@example.com": 2}
    print("{delivered.get_or("ada@example.com", 0)} deliveries")
    print("{delivered.get_or("new@example.com", 0)} deliveries")
    return 0
```

```text
2 recipients
2 deliveries
0 deliveries
```

The repeated address occupies one set entry. Map lookup finds the existing address and returns its count. For an absent address, `get_or` returns the chosen fallback `0`; it does not insert a new entry. Strings already have equality and hashing, so this program needs no custom implementation. If keys are application records, decide which fields define identity before using them in a map or set; [domain identity](#domain-identity) develops that choice below.

## Equality and hashing contracts

- `Equal`: values can be compared with `==` and `!=`. Records of the same type are equal when all fields are equal, not only when they are the same object.
- `Hashable`: a lookup code for map keys and set elements, which also require `Equal`. The hash finds the entry; equality resolves collisions.

Both are prelude interfaces from `@std/core.ms`; importing them is rejected. They are independent of sharing and resource lifetime.

`Comparable` (also in `@std/core.ms`) orders values for `math.max`, `math.min`, `List.sorted`, `List.min`, and `List.max`. It does not imply `Equal`: Float orders NaN above every value yet NaN != NaN. Make `compare` return zero exactly when `equals` is true.

These are reference signatures of the standard interfaces. They describe the built-in contracts; do not redeclare their reserved names in an application:

<!-- manuscript-artifact: {"kind":"schema"} -->
```manuscript
interface Equal:
    fn equals(other: Self) Bool

interface Comparable:
    fn compare(other: Self) Int

interface Hashable:
    fn hash() Int
```

`Self` is the implementing type. An implementation writes its own type for `other`, as `impl Equal for CustomerKey` does below, so it needs no match on the argument. In a bound `T: Equal`, `Self` is `T`: `left.equals(right)` takes two `T`. Through an `Equal` or `Comparable` value, `Self` is that interface: values of different types are unequal, and ordering them faults. `Self` is allowed only as a whole parameter or result type of an interface operation.

`==` and `!=` select the visible `Equal` implementation. A custom `Hashable` requires an `Equal`. Matching method names alone never establish either interface.

## Built-in value semantics

- `Bool`, `Int`, `Decimal`, `String`, `Bytes`, `Unit`, `Duration`, and `Instant` are built-in `Equal` and `Hashable`; `Never` vacuously is.
- Float has IEEE equality (NaN is unequal, `0.0 == -0.0`) and no hashing.
- Strings compare exact Unicode scalars, without normalization. Decimal compares numeric value. Instants must share a clock domain.
- Records, enums, Optional, and Result compare nominal type and all components, and satisfy each interface when all components do.

| Collection | Equality | Hashing |
| --- | --- | --- |
| `List[T]` | Equal corresponding elements in order | Unsupported |
| `Map[K, V]` | Equal associations, independent of insertion order | Unsupported |
| `Set[T]` | Equal members, independent of insertion order | Unsupported |

Equality reads both collections. The ownership rules prevent mutating a collection while it is borrowed for comparison.

- Recursive comparisons have a depth limit; see [programming faults](../errors/faults.md#runaway-recursion). Ownership prevents constructing cyclic values.
- Collections and recursive types get no automatic hashing; an explicit pair may hash a stable identity.
- Functions, resource handles, and service handles have no implicit equality.
- Compare through an `Equal`-typed parameter or binding with `.equals`.

## Domain identity

A customer can change their display label without becoming a different customer. If the identifier is the stable identity, compare and hash that identifier. An explicit implementation can select identity instead of every field:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"true\n12\n1\n"} -->
```manuscript
type CustomerKey:
    id: Int
    label: String

impl Equal for CustomerKey:
    fn equals(other: CustomerKey) Bool:
        return self.id == other.id

impl Hashable for CustomerKey:
    fn hash() Int: self.id

export fn main() Int:
    let first = CustomerKey(1, "Ada")
    let renamed = CustomerKey(1, "Ada Lovelace")
    print(first == renamed)
    let totals = {first.clone(): 12}
    print(totals.get_or(renamed, 0))
    let values = Set([first, renamed])
    print(values.length())
    return 0
```

```text
true
12
1
```

The records compare equal despite their different labels. The renamed key finds the same map entry, and the set keeps one customer. The map owns a clone of `first` because the original is still needed to construct the set; equality does not imply shared ownership. `equals` and `hash` both use `id`, so equal keys have equal hashes.

These implementations apply to operators, collection searches, and key lookup. Overriding equality disables automatic hashing, so provide a matching `hash` before using the type as a key. Visibility follows [contract rules](contracts.md#coherence-and-visibility).

## Key consistency

Equality must be reflexive, symmetric, and transitive, and equal values must hash equally. Hashes are lookup aids, not stable IDs or a serialization format.

Map keys and Set elements are owned by the collection. Inserting a non-scalar value moves it at its last use; clone it explicitly if you need an independent value afterwards.

Never change a stored key's equality or hash. Remove it, mutate, and reinsert; a mutated key stays filed under its old hash and neither value finds it. Equality and hash must be deterministic and independent of authority, resource state, and wall-clock time.
