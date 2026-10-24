# conform: tags=closures,control-flow,faults,formatter,generics,interfaces,lists,modules,optional,parser,records,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/contextual-generics.ms
from "@std/core.ms" import TextError
from "@std/testing.ms" import expect_equal, expect_false

def fail[T](message: String) -> Result[T, TextError]: error(TextError(message))

def fail_cause[T, E: Error](cause: E) -> Result[T, E]: error(cause)

def absent[T]() -> Optional[T]: none

def identity[T](value: T) -> T: value

def from_callback[T](factory: Callable[[], T]) -> T: factory()

def transform[T, U](callback: Callable[[T], U]) -> Callable[[T], U]: callback

type Failure:
    detail: String

impl Error for Failure:
    def message() -> ref String: self.detail

def first() -> Result[List[Int], TextError]: fail("empty")

def failed() -> Result[Int, Error]: fail_cause(Failure("domain"))

def forward[T]() -> Optional[T]: absent()

def consume(value: Optional[Int]) -> Int: value.get(0)

type Events:
    values: List[Int]

def record[T](var events: Events, value: Int) -> Optional[T]:
    events.values.append(value)
    return none

def combine[T](var events: Events, first: Optional[T], second: Optional[T]) -> Optional[
    T
]:
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

    let values: List[Optional[Int]] = [1, 2].map(lambda item: absent())
    try expect_equal(values.length(), 2)
    try expect_false(not values.get(0).is_none())

    let callback: Callable[[Int], String] = transform(lambda item: item.to_string())
    try expect_equal(callback(7), "7")

    let defaulted: Callable[[Int], Int] = from_callback(
        lambda: lambda (value: Int = 4): (value + 1)
    )
    try expect_equal(defaulted(8), 9)
    try expect_equal(consume(identity(5)), 5)

    var events = Events([])
    let combined: Optional[Int] = combine(
        var events, second: record(var events, 2), first: record(var events, 1)
    )
    try expect_false(not combined.is_none())
    try expect_equal(events.values, [2, 1, 3])
