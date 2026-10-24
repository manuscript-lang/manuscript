# conform: tags=closures,control-flow,faults,generics,interfaces,lists,modules,optional,records,stdlib-errors,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/contextual-callbacks.ms
from "@std/core.ms" import TextError
from "@std/testing.ms" import expect_equal, expect_false

def apply[T, U](value: T, transform: Callable[[T], U]) -> U: transform(value)

def chain[T, U](first: Callable[[], T], second: Callable[[T], U]) -> U: second(first())

def with_result[T](transform: Callable[[], Result[T, TextError]]) -> Result[T, TextError]: transform()

def checked() -> Result[Int, TextError]: ok(3)

type Box[T]:
    value: T

type Callback[T, U]:
    transform: Callable[[T], U]

interface Read:
    def get() -> Int

impl Read for Box[Int]:
    def get() -> Int: self.value

def invoke(transform: Optional[Callable[[Int], Int]] = none) -> Int:
    if let callback = transform:
        return callback(4)

    return 0

test "contextual callbacks and inline returns":
    let offset = 3
    let strings = (
        [1, 2, 3]
        .filter(lambda item: item > 1)
        .map(lambda number: (number + offset).to_string())
    )
    try expect_equal(strings.join(","), "5,6")

    let result = apply(transform: lambda item: item + offset, value: 2)
    try expect_equal(result, 5)
    try expect_equal(chain(second: lambda item: item + 2, first: lambda: 3), 5)

    let callback = Callback(lambda (item: Int): item + 1)
    try expect_equal(callback.transform(3), 4)

    let view = Read(Box(7))
    try expect_equal(view.get(), 7)
    try expect_false(invoke() != 0 or invoke(lambda item: item + 1) != 5)

    let functions: List[Callable[[Int], Int]] = [lambda item: item + 4]
    try expect_equal(functions.get(0)(2), 6)

    let nested = lambda (value: Int):
        let inner = lambda: "text"
        return value + inner().scalar_length()

    try expect_equal(nested(2), 6)

    let success = with_result(lambda: ok(4))
    try expect_equal(success, Result[Int, TextError].ok(4))

    let propagated = with_result(
        lambda:
            let value = try checked()
            return ok(value + 2)
    )

    try expect_equal(propagated, Result[Int, TextError].ok(5))

    let failed = with_result(
        lambda:
            if True: return error(TextError("expected"))

            return ok(4)
    )

    try expect_equal(failed, Result[Int, TextError].error(TextError("expected")))

    let subtract: Callable[[Int, Int], Int] = lambda a, b: a - b
    try expect_equal(subtract(7, 2), 5)

    let defaulted: Callable[[Int], Int] = lambda (item: Int = 4): item + 1
    try expect_equal(defaulted(8), 9)

    let outer: Callable[[Int], Callable[[Int], Int]] = lambda base:
        return lambda extra: base + extra
    try expect_equal(outer(3)(4), 7)
