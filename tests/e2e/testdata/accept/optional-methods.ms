import {expect_equal, expect_false} from "@std/test.ms"
import JsonLimits from "@std/json.ms"

type Counter:
    calls: Int

fn fallback(var counter: Counter) Int:
    counter.calls += 1
    return 42

fn value_or[T](value: Optional[T], fallback: T) T:
    if let inner = value:
        return inner

    return fallback

fn increment(value: Int) Int: value + 1

test "Optional presence and extraction preserve false and zero":
    let present: Optional[Int] = some(0)
    let missing: Optional[Int] = none
    try expect_false(not (present.is_some()))
    try expect_false(present.is_none())
    try expect_false(missing.is_some())
    try expect_false(not (missing.is_none()))
    try expect_equal(present.get(), 0)

    let flag: Optional[Bool] = some(false)
    try expect_false(flag.get())
    try expect_equal(value_or(missing, 7), 7)
    try expect_equal(value_or(present, 7), 0)
    try expect_false(missing.is_some())

test "Optional fallbacks distinguish eager and lazy evaluation":
    let present: Optional[Int] = some(0)
    let missing: Optional[Int] = none
    var counter = Counter(0)
    try expect_equal(present.get(fallback(var counter)), 0)
    try expect_equal(counter.calls, 1)

    let create = fn: some(42)
    try expect_equal(present.or_else(create).get(), 0)
    try expect_equal(missing.or_else(create).get(), 42)

test "Optional methods retain generic payload and receiver identity":
    let inner: Optional[Int] = none
    let outer: Optional[Optional[Int]] = some(inner)
    try expect_false(not (outer.is_some()))
    try expect_false(not (outer.get().is_none()))

    let counter = Counter(3)
    let record: Optional[Counter] = some(counter.clone())
    try expect_equal(record.get().calls, 3)

    let extract = record.get
    try expect_equal(extract().calls, 3)

    let callback: Optional[fn(Int) Int] = some(increment)
    try expect_equal(callback.get()(2), 3)

    let snapshot = outer.clone()
    try expect_equal(snapshot, outer)

test "Optional fallbacks preserve standard option records":
    let limits = JsonLimits(-1)
    let missing: Optional[JsonLimits] = none
    var extracted = missing.get(limits).clone()
    try expect_equal(extracted.max_bytes.get(), -1)
    try expect_false(not (extracted.max_depth.is_none()))
    extracted.max_values = some(7)
    try expect_equal(extracted.max_values.get(), 7)

test "Optional methods work on inferred library return values":
    let values = [1, 2]
    try expect_equal(values.get(0), 1)
    try expect_equal(values.get(5, default: 9), 9)
