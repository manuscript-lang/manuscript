import TextError from "@std/core.ms"
import expect_equal, expect_false from "@std/test.ms"

fn apply[T, U](value: T, transform: fn(T) U) U: transform(value)

fn choose[T](first: fn() T, second: fn() T) T: first()

fn optional[T, U](value: T, transform: (fn(T) U)?) U:
    return transform.get()(value)

fn with_result[T](transform: fn() Result[T, TextError]) Result[T, TextError]: transform()

type Callback[T, U]:
    transform: fn(T) U

type Failure[T]:
    detail: T

impl Error for Failure[T]:
    fn message() String: self.detail.to_string()

test "callback inference retains captures and contextual metadata":
    let offset = 7
    let values = [1, 2].map(
        fn outer: [3, 4].map(fn inner: return outer + inner + offset)
    )
    try expect_equal(values, [[11, 12], [12, 13]])

    let callable: fn(Int) fn(Int) Int = apply(
        value: 1, transform: fn base: fn item: fn extra: item + extra + base
    )
    try expect_equal(callable(3)(4), 8)

    let callback = Callback(fn(item: Int = 4): item + offset)
    try expect_equal(callback.transform(3), 10)
    try expect_equal(optional(value: 5, transform: fn item: item + offset), 12)

    let missing = choose(first: fn: none, second: fn() Int?: 3)
    try expect_false(not missing.is_none())

    let failure = with_result(
        fn:
            if true: return error(TextError("expected"))

            return ok(4)
    )

    try expect_equal(failure, Result[Int, TextError].error(TextError("expected")))

    let failed: Result[Int, Error] = apply(
        value: 9, transform: fn item: error(Failure(item))
    )
    try expect_false(failed.is_ok())
    try expect_equal(failed.err().message(), "9")

fn absent[T]() T?: none

fn from_callback[T](factory: fn() T) T: factory()

test "later returns repair incomplete and convertible evidence":
    let value = from_callback(
        fn:
            if true: return absent()

            let one: Int? = 1
            return one
    )

    try expect_false(not value.is_none())

    let cause = from_callback(
        fn:
            if false: return Failure(1)

            return Failure(2)
    )

    try expect_equal(cause.message(), "2")

fn operation() Result[Int, TextError]: ok(4)

test "try rechecks the inferred enclosing result":
    let value = from_callback(
        fn:
            let number = try operation()
            return Result[Int, TextError].ok(number)
    )

    try expect_equal(value, Result[Int, TextError].ok(4))
