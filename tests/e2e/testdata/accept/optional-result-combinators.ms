from "@std/testing.ms" import expect_equal, expect_false
from "@std/core.ms" import TextError, panic

type Counter:
    calls: Int

type Wrapped:
    inner: String

impl Error for Wrapped:
    def message() -> String: f"wrapped {self.inner}"

def tick(var counter: Counter) -> Int:
    counter.calls += 1
    return 7

def widen(cause: TextError) -> Wrapped: Wrapped(cause.message())

def parse(ok_value: Bool) -> Result[Int, TextError]:
    if ok_value:
        return ok(5)

    return error(TextError("bad"))

def convert(ok_value: Bool) -> Result[Int, Wrapped]:
    let value = try parse(ok_value).map_error(widen)
    return ok(value + 1)

def unexpected_int() -> Int: panic("closure must not run")

def unexpected_optional() -> Optional[Int]: panic("closure must not run")

def unexpected_recover(cause: TextError) -> Result[Int, TextError]:
    return panic("closure must not run")

def unexpected_text(cause: TextError) -> Int: panic("closure must not run")

def unexpected_widen(cause: TextError) -> Wrapped: panic("closure must not run")

test "Optional get_or_else returns the payload and is lazy":
    let present: Optional[Int] = some(0)
    let missing: Optional[Int] = none
    var counter = Counter(0)
    try expect_equal(present.get_or_else(unexpected_int), 0)
    try expect_equal(missing.get_or_else(lambda: tick(var counter)), 7)
    try expect_equal(counter.calls, 1)

    let flag: Optional[Bool] = some(False)
    try expect_false(flag.get_or_else(lambda: True))

test "Optional or_else keeps the wrapper and is lazy":
    let present: Optional[Int] = some(0)
    let missing: Optional[Int] = none
    try expect_equal(present.or_else(unexpected_optional), some(0))
    try expect_equal(missing.or_else(lambda: some(4)), some(4))
    try expect_equal(missing.or_else(lambda: Optional[Int].none), none)

test "Result get_or_else returns the payload and receives the error":
    let success: Result[Int, TextError] = ok(0)
    let failure: Result[Int, TextError] = error(TextError("failed"))
    try expect_equal(success.get_or_else(unexpected_text), 0)
    try expect_equal(
        failure.get_or_else(lambda cause: cause.message().scalar_length()), 6
    )

test "Result or_else keeps the wrapper and is lazy":
    let success: Result[Int, TextError] = ok(1)
    let failure: Result[Int, TextError] = error(TextError("failed"))
    try expect_equal(success.or_else(unexpected_recover), success)
    try expect_equal(failure.or_else(lambda cause: ok(9)), ok(9))

    let still: Result[Int, TextError] = failure.or_else(
        lambda cause: error(TextError("again"))
    )
    try expect_equal(still.err().message(), "again")

test "Result map_error converts the error type and feeds try":
    let success: Result[Int, TextError] = ok(3)
    let failure: Result[Int, TextError] = error(TextError("bad"))
    try expect_equal(success.map_error(unexpected_widen).get(), 3)
    try expect_equal(failure.map_error(widen).err().inner, "bad")
    try expect_equal(convert(True).get(), 6)
    try expect_equal(convert(False).err().message(), "wrapped bad")

test "map and and_then on both types keep their meaning":
    let present: Optional[Int] = some(2)
    let success: Result[Int, TextError] = ok(2)
    try expect_equal(present.map(lambda n: n + 1).get(), 3)
    try expect_equal(present.and_then(lambda n: some(n * 2)).get(), 4)
    try expect_equal(success.map(lambda n: n + 1).get(), 3)
    try expect_equal(success.and_then(lambda n: ok(n * 2)).get(), 4)
