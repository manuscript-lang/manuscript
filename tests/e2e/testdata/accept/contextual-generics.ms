import TextError from "@std/core.ms"
import expect_equal, expect_false from "@std/test.ms"

fn fail[T](message: String) Result[T, TextError]: error(TextError(message))

fn fail_cause[T, E: Error](cause: E) Result[T, E]: error(cause)

fn absent[T]() Optional[T]: none

fn identity[T](value: T) T: value

fn from_callback[T](factory: fn() T) T: factory()

fn transform[T, U](callback: fn(T) U) fn(T) U: callback

type Failure:
    detail: String

impl Error for Failure:
    fn message() String: self.detail.clone()

fn first() Result[List[Int], TextError]: fail("empty")

fn failed() Result[Int, Error]: fail_cause(Failure("domain"))

fn forward[T]() Optional[T]: absent()

fn consume(value: Optional[Int]) Int: value.get(0)

type Events:
    values: List[Int]

fn record[T](var events: Events, value: Int) Optional[T]:
    events.values.append(value)
    return none

fn combine[T](var events: Events, first: Optional[T], second: Optional[T]) Optional[T]:
    events.values.append(3)
    return first

test "expected generic results preserve behavior and call order":
    let result: Result[List[Int], TextError] = first()
    try expect_false(result.is_ok())
    try expect_equal(result.err().message(), "empty")

    let domain = failed()
    try expect_false(domain.is_ok())
    try expect_equal(domain.err().message(), "domain")

    let empty: Optional[Int] = forward()
    try expect_false(not empty.is_none())

    let values: List[Optional[Int]] = [1, 2].map(fn item: absent())
    try expect_equal(values.length(), 2)
    try expect_false(not values.get(0).is_none())

    let callback: fn(Int) String = transform(fn item: item.to_string())
    try expect_equal(callback(7), "7")

    let defaulted: fn(Int) Int = from_callback(fn: fn(value: Int = 4): (value + 1))
    try expect_equal(defaulted(8), 9)
    try expect_equal(consume(identity(5)), 5)

    var events = Events([])
    let combined: Optional[Int] = combine(
        var events, second: record(var events, 2), first: record(var events, 1)
    )
    try expect_false(not combined.is_none())
    try expect_equal(events.values, [2, 1, 3])
