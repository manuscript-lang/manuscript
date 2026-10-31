import expect_equal, expect_false from "@std/test.ms"
import TextError, panic from "@std/core.ms"

type Counter:
    calls: Int

type Wrapped:
    inner: String

impl Error for Wrapped:
    fn message() String: "wrapped {self.inner}"

fn tick(var counter: Counter) Int:
    counter.calls += 1
    return 7

fn widen(cause: TextError) Wrapped: Wrapped(cause.message())

fn parse(ok_value: Bool) Result[Int, TextError]:
    if ok_value:
        return ok(5)

    return error(TextError("bad"))

fn convert(ok_value: Bool) Result[Int, Wrapped]:
    let value = try parse(ok_value).map_error(widen)
    return ok(value + 1)

fn unexpected_int() Int: panic("closure must not run")

fn unexpected_optional() Int?: panic("closure must not run")

fn unexpected_recover(cause: TextError) Result[Int, TextError]:
    return panic("closure must not run")

fn unexpected_text(cause: TextError) Int: panic("closure must not run")

fn unexpected_widen(cause: TextError) Wrapped: panic("closure must not run")

test "Optional get_or_else returns the payload and is lazy":
    let present: Int? = 0
    let missing: Int? = none
    var counter = Counter(0)
    try expect_equal(present.get_or_else(unexpected_int), 0)
    try expect_equal(missing.get_or_else(fn: tick(var counter)), 7)
    try expect_equal(counter.calls, 1)

    let flag: Bool? = false
    try expect_false(flag.get_or_else(fn: true))

test "Optional or_else keeps the wrapper and is lazy":
    let present: Int? = 0
    let missing: Int? = none
    try expect_equal(present.or_else(unexpected_optional), 0)
    try expect_equal(missing.or_else(fn: 4), 4)
    try expect_equal(missing.or_else(fn: none), none)

test "Result get_or_else returns the payload and receives the error":
    let success: Result[Int, TextError] = ok(0)
    let failure: Result[Int, TextError] = error(TextError("failed"))
    try expect_equal(success.get_or_else(unexpected_text), 0)
    try expect_equal(failure.get_or_else(fn cause: cause.message().scalar_length()), 6)

test "Result or_else keeps the wrapper and is lazy":
    let success: Result[Int, TextError] = ok(1)
    let failure: Result[Int, TextError] = error(TextError("failed"))
    try expect_equal(success.or_else(unexpected_recover), success)
    try expect_equal(failure.or_else(fn cause: ok(9)), ok(9))

    let still: Result[Int, TextError] = failure.or_else(
        fn cause: error(TextError("again"))
    )
    try expect_equal(still.err().message(), "again")

test "Result map_error converts the error type and feeds try":
    let success: Result[Int, TextError] = ok(3)
    let failure: Result[Int, TextError] = error(TextError("bad"))
    try expect_equal(success.map_error(unexpected_widen).get(), 3)
    try expect_equal(failure.map_error(widen).err().inner, "bad")
    try expect_equal(convert(true).get(), 6)
    try expect_equal(convert(false).err().message(), "wrapped bad")

test "map and and_then on both types keep their meaning":
    let present: Int? = 2
    let success: Result[Int, TextError] = ok(2)
    try expect_equal(present.map(fn n: n + 1).get(), 3)
    try expect_equal(present.and_then(fn(n: Int) Int?: n * 2).get(), 4)
    try expect_equal(success.map(fn n: n + 1).get(), 3)
    try expect_equal(success.and_then(fn n: ok(n * 2)).get(), 4)
