+++
title = "Minimum data operations"
weight = 39
+++

# Minimum data operations

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

This is the reference for basic methods on standard data types. These methods belong to the canonical intrinsic or imported receiver type. They do not introduce new global names or compiler bounds.

Import standard types when naming them. Ordinary bracket list literals need `List`. A type inferred from a return value does not need its own import unless you name it in source. Updates produce new immutable values and leave the original unchanged. Sizes and indexes use `Int`; allocation failure is a host failure.

A single-parameter operation may omit its argument label. Multi-parameter operations require the exact labels below.

## Collections

| Receiver or constructor | Signature/result |
| --- | --- |
| `List[T]` | `length() -> Int`; `get(index: Int) -> Optional[T]` |
| `List[T]` | `append(value: T) -> List[T]`; `concat(values: List[T]) -> List[T]` |
| `Map[K, V]()` | Empty `Map[K, V]` |
| `Map[K, V]` | `length() -> Int`; `get(key: K) -> Optional[V]`; `contains(key: K) -> Bool` |
| `Map[K, V]` | `with_entry(key: K, value: V) -> Map[K, V]`; `without(key: K) -> Map[K, V]` |
| `Set[T]()` | Empty `Set[T]` |
| `Set[T]` | `length() -> Int`; `contains(value: T) -> Bool` |
| `Set[T]` | `with_value(value: T) -> Set[T]`; `without(value: T) -> Set[T]` |

All existing element and key bounds apply. An empty Map/Set constructor requires explicit type arguments or a complete expected application; it supplies no inference evidence by itself. List construction uses the existing bracket literal. Negative or out-of-range list indexes return `none`. A size exceeding MaxInt64 faults.

Maps and sets traverse in insertion order. Replacing an equal map key retains its original key value and first insertion position; adding an existing set element retains its original value and position. Removing an absent key/element is a value-preserving operation. Removing and then adding places the new entry at the end. Equality remains independent of insertion order. A simple implementation may copy storage on update; builder APIs are specified separately once their signatures are settled.

```manuscript
import panic from "@std/faults.ms"

import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Optional from "@std/optional.ms"

fn positives(values: List[Int]) -> List[Int]:
    var result: List[Int] = []
    for value in values:
        if value > 0:
            result = result.append(value: value)
    return result

test "dynamic immutable data":
    if not (positives(values: [3, -1, 2]) == [3, 2]):
        return panic(message: "check failed")
    let absent: Optional[Int] = none
    if not ([1].get(index: 5) == absent):
        return panic(message: "check failed")
    let original = Map[String, Int]().with_entry(key: "a", value: 1)
    let updated = original.with_entry(key: "b", value: 2).with_entry(key: "a", value: 3)
    if not (original.get(key: "a") == some(value: 1)):
        return panic(message: "check failed")
    if not (updated.get(key: "a") == some(value: 3)):
        return panic(message: "check failed")
```

## Strings and bytes

| Receiver or constructor | Signature/result |
| --- | --- |
| `String` | `byte_length() -> Int`; `to_bytes() -> Bytes`; `parse_int() -> Optional[Int]` |
| `Bytes(values: List[Int])` | Immutable bytes; each value must be 0–255, otherwise a programming fault |
| `Bytes` | `length() -> Int`; `get(index: Int) -> Optional[Int]`; `concat(values: Bytes) -> Bytes` |
| `Bytes` | `to_text() -> Optional[String]` |

`String.to_bytes` uses UTF-8. `Bytes.to_text` succeeds exactly for valid UTF-8, preserving contents without normalization; invalid bytes produce `none`. Byte `get` follows list index behavior and returns the unsigned byte as Int. An empty `Bytes(values: [])` is valid.

`parse_int` accepts exactly an optional ASCII `+` or `-` followed by one or more ASCII decimal digits and an in-range mathematical value. It permits leading zeros, rejects whitespace, separators, fractions, exponents, and any unconsumed character, and returns `none` for invalid or out-of-range input. Runtime parsing is distinct from the stricter source literal grammar. Scalar/grapheme indexing and additional parsing/formatting APIs are unsupported.

```manuscript
import panic from "@std/faults.ms"

import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"
import Optional from "@std/optional.ms"

test "explicit byte conversion":
    if not ("é".byte_length() == 2):
        return panic(message: "check failed")
    if not ("é".to_bytes().to_text() == some(value: "é")):
        return panic(message: "check failed")
    let invalid: Optional[String] = none
    if not (Bytes(values: [255]).to_text() == invalid):
        return panic(message: "check failed")
    if not ("-007".parse_int() == some(value: -7)):
        return panic(message: "check failed")
```

## Numeric and time conversion

| Receiver | Signature/result |
| --- | --- |
| `Int` | `to_float() -> Float`; `to_decimal() -> Decimal` |
| `Float` | `truncate_to_int() -> Optional[Int]` |
| `Decimal` | `to_float() -> Float`; `truncate_to_int() -> Optional[Int]` |
| `Int` | `milliseconds`, `seconds`, `minutes` members producing `Duration` |

Int→Decimal is exact. Int→Float and Decimal→Float round once to nearest binary64, ties to even. Decimal→Float may produce signed infinity or signed zero under the Float rules. Truncation discards the fractional part toward zero, then checks the mathematical integer against the exact signed 64-bit limits before conversion. NaN, infinities, or an out-of-range integer yield `none`; do not compare against a rounded Float representation of MaxInt64 and then use a Go cast.

`Duration` is a signed 64-bit count of nanoseconds. The three unit members work on any Int expression and multiply by 1,000,000, 1,000,000,000, or 60,000,000,000 with overflow checks. `Instant` is an opaque monotonic instant in the current run's clock domain; it has no source constructor. Clock adapters and injected test clocks must preserve a single comparable domain within a run. Cross-domain comparison or subtraction faults. Duration arithmetic and Instant shifts/differences check overflow; these compiler-defined operations are enumerated in the [operator table](../../core-language/basics/expressions.md).

Boundary expectations: `1e300.truncate_to_int()` is `none`; converting Float +2^63 to Int is `none`, while Float -2^63 succeeds. `2.seconds` is 2,000,000,000 nanoseconds. Unsupported unit names and mixed arithmetic such as `2.seconds + 1` are type errors.
