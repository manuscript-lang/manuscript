# conform: tags=closures,control-flow,faults,generics,interfaces,lists,modules,optional,records,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/callback-probe-reuse.ms
from "@std/core.ms" import TextError
from "@std/testing.ms" import expect_equal, expect_false

def apply[T, U](value: T, transform: Callable[[T], U]) -> U: transform(value)

def choose[T](first: Callable[[], T], second: Callable[[], T]) -> T: first()

def optional[T, U](value: T, transform: Optional[Callable[[T], U]]) -> U:
    return transform.get()(value)

def with_result[T](
    transform: Callable[[], Result[T, TextError]]
) -> Result[T, TextError]: transform()

type Callback[T, U]:
    transform: Callable[[T], U]

type Failure[T]:
    detail: T

impl Error for Failure[T]:
    def message() -> String: self.detail.to_string()

test "callback inference retains captures and contextual metadata":
    let offset = 7
    let values = [1, 2].map(
        lambda outer: [3, 4].map(lambda inner: return outer + inner + offset)
    )
    try expect_equal(values, [[11, 12], [12, 13]])

    let callable: Callable[[Int], Callable[[Int], Int]] = apply(
        value: 1, transform: lambda base: lambda item: lambda extra: item + extra + base
    )
    try expect_equal(callable(3)(4), 8)

    let callback = Callback(lambda (item: Int = 4): item + offset)
    try expect_equal(callback.transform(3), 10)
    try expect_equal(optional(value: 5, transform: lambda item: item + offset), 12)

    let missing = choose(first: lambda: none, second: lambda: some(3))
    try expect_false(not missing.is_none())

    let failure = with_result(
        lambda:
            if True: return error(TextError("expected"))

            return ok(4)
    )

    try expect_equal(failure, Result[Int, TextError].error(TextError("expected")))

    let failed: Result[Int, Error] = apply(
        value: 9, transform: lambda item: error(Failure(item))
    )
    try expect_false(failed.is_ok())
    try expect_equal(failed.err().message(), "9")

def absent[T]() -> Optional[T]: none

def from_callback[T](factory: Callable[[], T]) -> T: factory()

test "later returns repair incomplete and convertible evidence":
    let value = from_callback(
        lambda:
            if True: return absent()

            return some(1)
    )

    try expect_false(not value.is_none())

    let cause = from_callback(
        lambda:
            if False: return Failure(1)

            return Failure(2)
    )

    try expect_equal(cause.message(), "2")

def operation() -> Result[Int, TextError]: ok(4)

test "try rechecks the inferred enclosing result":
    let value = from_callback(
        lambda:
            let number = try operation()
            return Result[Int, TextError].ok(number)
    )

    try expect_equal(value, Result[Int, TextError].ok(4))
