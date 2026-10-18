import {expect_equal} from "@std/testing.ms"

fn identity[T](value: T) -> T: value

fn first[T](left: T, right: T) -> T: left

fn optional[T](value: Optional[T], fallback: T) -> T: value.unwrap_or(fallback)

fn describe[T](value: T, cause: Error) -> String: cause.message()

type Events:
    values: List[Int]

type Failure:
    detail: String

impl Error for Failure:
    fn message() -> String: self.detail

type GenericFailure[T]:
    detail: T

impl Error for GenericFailure[T]:
    fn message() -> String: self.detail.toString()

fn record(events: Events, value: Int) -> Int:
    events.values = events.values.append(value)
    return value

test "reused inference preserves evaluation and argument conversions":
    let events = Events([])
    let selected = first(
        right: identity(identity(record(events: events, value: 2))),
        left: identity(identity(record(events: events, value: 1)))
    )
    selected | try expect_equal(expected: 1)
    events.values | try expect_equal(expected: [2, 1])
    let wrapped = optional(
        value: identity(record(events: events, value: 3)),
        fallback: 0
    )
    wrapped | try expect_equal(expected: 3)
    events.values | try expect_equal(expected: [2, 1, 3])
    let message = describe(value: 1, cause: identity(Failure("cached")))
    message | try expect_equal(expected: "cached")
    let generic_message = describe(value: 1, cause: identity(GenericFailure(4)))
    generic_message | try expect_equal(expected: "4")
    let offset = 7
    let callback = identity(identity(fn(value: Int): offset + value))
    callback(3) | try expect_equal(expected: 10)
