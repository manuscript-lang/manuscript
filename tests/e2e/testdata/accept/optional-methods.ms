import {expect_equal, expect_false, expect_true} from "@std/testing.ms"
import JsonLimits from "@std/json.ms"

type Counter:
    calls: Int

fn fallback(counter: Counter) -> Int:
    counter.calls = counter.calls + 1
    return 42

fn value_or[T](value: Optional[T], fallback: T) -> T:
    return value.unwrap_or(fallback)

fn increment(value: Int) -> Int: value + 1

test "Optional presence and extraction preserve false and zero":
    let present: Optional[Int] = some(0)
    let missing: Optional[Int] = none
    (present.is_some()) | try expect_true
    present.is_none() | try expect_false
    missing.is_some() | try expect_false
    (missing.is_none()) | try expect_true
    present.unwrap() | try expect_equal(expected: 0)
    let flag: Optional[Bool] = some(false)
    flag.unwrap() | try expect_false
    value_or(value: missing, fallback: 7) | try expect_equal(expected: 7)
    value_or(value: present, fallback: 7) | try expect_equal(expected: 0)
    missing.is_some() | try expect_false

test "Optional fallbacks distinguish eager and lazy evaluation":
    let present: Optional[Int] = some(0)
    let missing: Optional[Int] = none
    let counter = Counter(0)
    present.unwrap_or(fallback(counter)) | try expect_equal(expected: 0)
    counter.calls | try expect_equal(expected: 1)
    let create = fn(): fallback(counter)
    present.unwrap_or_else(create) | try expect_equal(expected: 0)
    counter.calls | try expect_equal(expected: 1)
    missing.unwrap_or_else(create) | try expect_equal(expected: 42)
    counter.calls | try expect_equal(expected: 2)

test "Optional methods retain generic payload and receiver identity":
    let inner: Optional[Int] = none
    let outer: Optional[Optional[Int]] = some(inner)
    (outer.is_some()) | try expect_true
    (outer.unwrap().is_none()) | try expect_true
    let counter = Counter(0)
    let record: Optional[Counter] = some(counter)
    record.unwrap().calls = 3
    counter.calls | try expect_equal(expected: 3)
    let extract = record.unwrap
    extract().calls = 4
    counter.calls | try expect_equal(expected: 4)
    let callback: Optional[fn(value: Int) -> Int] = some(increment)
    callback.unwrap()(2) | try expect_equal(expected: 3)
    let snapshot = outer.clone()
    snapshot | try expect_equal(expected: outer)

test "Optional fallbacks preserve standard option records":
    let limits = JsonLimits(max_bytes: -1)
    let missing: Optional[JsonLimits] = none
    let extracted = missing.unwrap_or(limits)
    extracted.max_bytes.unwrap() | try expect_equal(expected: -1)
    (extracted.max_depth.is_none()) | try expect_true
    extracted.max_values = some(7)
    limits.max_values.unwrap() | try expect_equal(expected: 7)

test "Optional methods work on inferred library return values":
    let values = [1, 2]
    values.at(0).unwrap() | try expect_equal(expected: 1)
    values.at(5).unwrap_or(9) | try expect_equal(expected: 9)
