import {expect_equal, expect_false} from "@std/testing.ms"

fn apply[T, U](value: T, transform: fn(value: T) -> U) -> U: transform(value)

fn chain[T, U](first: fn() -> T, second: fn(value: T) -> U) -> U: second(first())

fn with_result[T](transform: fn() -> Result[T, String]) -> Result[T, String]: transform()

fn checked() -> Result[Int, String]: ok(3)

type Box[T]:
    value: T

type Callback[T, U]:
    transform: fn(value: T) -> U

interface Read:
    fn get() -> Int

impl Read for Box[Int]:
    fn get() -> Int: self.value

fn invoke(transform: Optional[fn(value: Int) -> Int] = none) -> Int:
    match transform:
        some(callback): return callback(4)
        none: return 0

test "contextual callbacks and inline returns":
    let offset = 3
    let strings = (
        [1, 2, 3]
        .filter(fn(item): item > 1)
        .map(fn(number): (number + offset).toString())
    )
    strings.join(",") | try expect_equal(expected: "5,6")
    let result = apply(transform: fn(item): item + offset, value: 2)
    result | try expect_equal(expected: 5)
    try expect_equal(chain(second: fn(item): item + 2, first: fn(): 3), 5)
    let callback = Callback(fn(item: Int): item + 1)
    callback.transform(3) | try expect_equal(expected: 4)
    let view = Read(Box(7))
    view.get() | try expect_equal(expected: 7)
    try expect_false(invoke() != 0 or invoke(fn(item): item + 1) != 5)
    let functions: List[fn(value: Int) -> Int] = [fn(item): item + 4]
    functions.at(0).unwrap()(2) | try expect_equal(expected: 6)
    let nested = fn(value: Int):
        let inner = fn(): "text"
        return value + inner().scalar_length()
    nested(2) | try expect_equal(expected: 6)
    let success = with_result(fn(): ok(4))
    success | try expect_equal(expected: Result[Int, String].ok(4))
    let propagated = with_result(
        fn():
            let value = try checked()
            return ok(value + 2)
    )
    propagated | try expect_equal(expected: Result[Int, String].ok(5))
    let failed = with_result(
        fn():
            if true: return error("expected")

            return ok(4)
    )
    failed | try expect_equal(expected: Result[Int, String].error("expected"))
    let subtract: fn(left: Int, right: Int) -> Int = fn(a, b): a - b
    subtract(right: 2, left: 7) | try expect_equal(expected: 5)
    let defaulted: fn(value: Int) -> Int = fn(item: Int = 4): item + 1
    defaulted(value: 8) | try expect_equal(expected: 9)
    let outer: fn(value: Int) -> fn(input: Int) -> Int = fn(base):
        return fn(extra): base + extra
    outer(value: 3)(input: 4) | try expect_equal(expected: 7)
