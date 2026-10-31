# conform: tags=closures,control-flow,faults,generics,interfaces,lists,modules,optional,records,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/contextual-generics.ms
import TextError from "@std/core.ms"
import expect_equal, expect_false from "@std/test.ms"

fn fail[T](message: String) T!TextError: error(TextError(message))

fn fail_cause[T, E: Error](cause: E) T!E: error(cause)

fn absent[T]() T?: none

fn identity[T](value: T) T: value

fn from_callback[T](factory: fn() T) T: factory()

fn transform[T, U](callback: fn(T) U) fn(T) U: callback

type Failure:
    detail: String

impl Error for Failure:
    fn message() String: self.detail.clone()

fn first() List[Int]!TextError: fail("empty")

fn failed() Int!: fail_cause(Failure("domain"))

fn forward[T]() T?: absent()

fn consume(value: Int?) Int: value.get(0)

type Events:
    values: List[Int]

fn record[T](var events: Events, value: Int) T?:
    events.values.append(value)
    return none

fn combine[T](var events: Events, first: T?, second: T?) T?:
    events.values.append(3)
    return first

test "expected generic results preserve behavior and call order":
    let result: List[Int]!TextError = first()
    try expect_false(result.is_ok())
    try expect_equal(result.err().message(), "empty")

    let domain = failed()
    try expect_false(domain.is_ok())
    try expect_equal(domain.err().message(), "domain")

    let empty: Int? = forward()
    try expect_false(not empty.is_none())

    let values: List[Int?] = [1, 2].map(fn item: absent())
    try expect_equal(values.length(), 2)
    try expect_false(not values.get(0).is_none())

    let callback: fn(Int) String = transform(fn item: item.to_string())
    try expect_equal(callback(7), "7")

    let defaulted: fn(Int) Int = from_callback(fn: fn(value: Int = 4): (value + 1))
    try expect_equal(defaulted(8), 9)
    try expect_equal(consume(identity(5)), 5)

    var events = Events([])
    let combined: Int? = combine(
        var events, second: record(var events, 2), first: record(var events, 1)
    )
    try expect_false(not combined.is_none())
    try expect_equal(events.values, [2, 1, 3])
