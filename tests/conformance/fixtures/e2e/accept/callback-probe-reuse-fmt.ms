# conform: tags=aliasing,closures,control-flow,faults,formatter,generics,interfaces,lists,modules,optional,parser,records,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/callback-probe-reuse.ms
import {TextError} from "@std/errors.ms"
import {expect_equal, expect_false} from "@std/testing.ms"

fn apply[T, U](value: T, transform: fn(value: T) U) U: transform(value)

fn choose[T](first: fn() T, second: fn() T) T: first()

fn optional[T, U](value: T, transform: Optional[fn(value: T) U]) U:
    return transform.get()(value)

fn with_result[T](transform: fn() Result[T, TextError]) Result[T, TextError]: transform()

type Callback[T, U]:
    transform: fn(value: T) U

type Events:
    values: List[Int]

type Failure[T]:
    detail: T

impl Error for Failure[T]:
    fn message() String: self.detail.to_string()

fn record(events: Events, value: Int) Int:
    events.values = events.values.append(value)
    return value

test "callback inference retains captures and contextual metadata":
    let events = Events([])
    let offset = 7
    let values = [1, 2].map(
        fn(outer): [3, 4].map(
            fn(inner):
                return record(events, value: outer + inner + offset)
        )
    )
    try expect_equal(values, [[11, 12], [12, 13]])
    try expect_equal(events.values, [11, 12, 12, 13])
    let callable: fn(value: Int) fn(input: Int) Int = apply(
        value: 1,
        transform: fn(base): fn(item): fn(extra): item + extra + base
    )
    try expect_equal(callable(value: 3)(input: 4), 8)
    let callback = Callback(fn(item: Int = 4): item + offset)
    try expect_equal(callback.transform(3), 10)
    try expect_equal(optional(value: 5, transform: fn(item): item + offset), 12)
    let missing = choose(first: fn(): none, second: fn(): some(3))
    try expect_false(not missing.is_none())
    let failure = with_result(
        fn():
            if true: return error(TextError("expected"))

            return ok(4)
    )
    try expect_equal(failure, Result[Int, TextError].error(TextError("expected")))
    let failed: Result[Int, Error] = apply(
        value: 9,
        transform: fn(item): error(Failure(item))
    )
    try expect_false(failed.is_ok())
    try expect_equal(failed.err().message(), "9")

fn absent[T]() Optional[T]: none

fn from_callback[T](factory: fn() T) T: factory()

test "later returns repair incomplete and convertible evidence":
    let value = from_callback(
        fn():
            if true: return absent()

            return some(1)
    )
    try expect_false(not value.is_none())
    let cause = from_callback(
        fn():
            if false: return Error(Failure(1))

            return Failure(2)
    )
    try expect_equal(cause.message(), "2")

fn operation() Result[Int, TextError]: ok(4)

test "try rechecks the inferred enclosing result":
    let value = from_callback(
        fn():
            let number = try operation()
            return Result[Int, TextError].ok(number)
    )
    try expect_equal(value, Result[Int, TextError].ok(4))
