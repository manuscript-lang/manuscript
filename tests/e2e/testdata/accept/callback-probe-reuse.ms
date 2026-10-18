import {expect_equal, expect_true, fail} from "@std/testing.ms"

fn apply[T, U](value: T, transform: fn(value: T) -> U) -> U: transform(value)

fn choose[T](first: fn() -> T, second: fn() -> T) -> T: first()

fn optional[T, U](value: T, transform: Optional[fn(value: T) -> U]) -> U:
    return transform.unwrap()(value)

fn with_result[T](transform: fn() -> Result[T, String]) -> Result[T, String]: transform()

type Callback[T, U]:
    transform: fn(value: T) -> U

type Events:
    values: List[Int]

type Failure[T]:
    detail: T

impl Error for Failure[T]:
    fn message() -> String: self.detail.toString()

fn record(events: Events, value: Int) -> Int:
    events.values = events.values.append(value)
    return value

test "callback inference retains captures and contextual metadata":
    let events = Events([])
    let offset = 7
    let values = [1, 2].map(
        fn(outer): [3, 4].map(
            fn(inner):
                return record(events: events, value: outer + inner + offset)
        )
    )
    values | try expect_equal(expected: [[11, 12], [12, 13]])
    events.values | try expect_equal(expected: [11, 12, 12, 13])
    let callable: fn(value: Int) -> fn(input: Int) -> Int = apply(
        value: 1,
        transform: fn(base): fn(item): fn(extra): item + extra + base
    )
    callable(value: 3)(input: 4) | try expect_equal(expected: 8)
    let callback = Callback(fn(item: Int = 4): item + offset)
    callback.transform(3) | try expect_equal(expected: 10)
    try expect_equal(optional(value: 5, transform: fn(item): item + offset), 12)
    let missing = choose(first: fn(): none, second: fn(): some(3))
    (missing.is_none()) | try expect_true
    let failure = with_result(
        fn():
            if true: return error("expected")

            return ok(4)
    )
    failure | try expect_equal(expected: Result[Int, String].error("expected"))
    let failed: Result[Int, Error] = apply(
        value: 9,
        transform: fn(item): error(Failure(item))
    )

    match failed:
        ok(_): return fail("expected domain failure")
        error(cause):
            try expect_equal(cause.message(), "9")

fn absent[T]() -> Optional[T]: none

fn from_callback[T](factory: fn() -> T) -> T: factory()

test "later returns repair incomplete and convertible evidence":
    let value = from_callback(
        fn():
            if true: return absent()

            return some(1)
    )
    (value.is_none()) | try expect_true
    let cause = from_callback(
        fn():
            if false: return Error(Failure(1))

            return Failure(2)
    )
    cause.message() | try expect_equal(expected: "2")

fn operation() -> Result[Int, String]: ok(4)

test "try rechecks the inferred enclosing result":
    let value = from_callback(
        fn():
            let number = try operation()
            return Result[Int, String].ok(number)
    )
    value | try expect_equal(expected: Result[Int, String].ok(4))
