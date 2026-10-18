import {expect_equal, expect_true, fail} from "@std/testing.ms"

fn generic_failure[T](message: String) -> Result[T, String]: error(message)

fn fail_cause[T, E](cause: E) -> Result[T, E]: error(cause)

fn absent[T]() -> Optional[T]: none

fn identity[T](value: T) -> T: value

fn from_callback[T](factory: fn() -> T) -> T: factory()

fn transform[T, U](callback: fn(value: T) -> U) -> fn(value: T) -> U: callback

type Failure:
    detail: String

impl Error for Failure:
    fn message() -> String: self.detail

fn first() -> Result[List[Int], String]: generic_failure("empty")

fn failed() -> Result[Int, Error]: fail_cause(Failure("domain"))

fn forward[T]() -> Optional[T]: absent()

fn consume(value: Optional[Int]) -> Int: value.unwrap_or(0)

type Events:
    values: List[Int]

fn record[T](events: Events, value: Int) -> Optional[T]:
    events.values = events.values.append(value)
    return none

fn combine[T](events: Events, first: Optional[T], second: Optional[T]) -> Optional[T]:
    events.values = events.values.append(3)
    return first

test "expected generic results preserve behavior and call order":
    let result: Result[List[Int], String] = first()

    match result:
        ok(_): return fail("expected failure")
        error(message):
            try expect_equal(message, "empty")

    match failed():
        ok(_): return fail("expected domain failure")
        error(cause):
            try expect_equal(cause.message(), "domain")

    let empty: Optional[Int] = forward()
    (empty.is_none()) | try expect_true
    let values: List[Optional[Int]] = [1, 2].map(fn(item): absent())
    values.length() | try expect_equal(expected: 2)
    (values.at(0).unwrap().is_none()) | try expect_true
    let callback: fn(value: Int) -> String = transform(fn(item): item.toString())
    callback(7) | try expect_equal(expected: "7")
    let defaulted: fn(value: Int) -> Int = from_callback(
        fn(): fn(value: Int = 4): (value + 1)
    )
    defaulted(8) | try expect_equal(expected: 9)
    consume(identity(5)) | try expect_equal(expected: 5)
    let events = Events([])
    let combined: Optional[Int] = combine(
        events: events,
        second: record(events: events, value: 2),
        first: record(events: events, value: 1)
    )
    (combined.is_none()) | try expect_true
    events.values | try expect_equal(expected: [2, 1, 3])
