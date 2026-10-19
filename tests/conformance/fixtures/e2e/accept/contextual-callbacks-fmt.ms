# conform: tags=aliasing,closures,control-flow,faults,formatter,generics,interfaces,lists,modules,optional,parser,records,stdlib-errors,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/contextual-callbacks.ms
import {TextError} from "@std/errors.ms"
import {expect_equal, expect_false} from "@std/testing.ms"

fn apply[T, U](value: T, transform: fn(value: T) U) U: transform(value)

fn chain[T, U](first: fn() T, second: fn(value: T) U) U: second(first())

fn with_result[T](transform: fn() Result[T, TextError]) Result[T, TextError]: transform()

fn checked() Result[Int, TextError]: ok(3)

type Box[T]:
    value: T

type Callback[T, U]:
    transform: fn(value: T) U

interface Read:
    fn get() Int

impl Read for Box[Int]:
    fn get() Int: self.value

fn invoke(transform: Optional[fn(value: Int) Int] = none) Int:
    if let callback = transform:
        return callback(4)

    return 0

test "contextual callbacks and inline returns":
    let offset = 3
    let strings = (
        [1, 2, 3]
        .filter(fn(item): item > 1)
        .map(fn(number): (number + offset).to_string())
    )
    try expect_equal(strings.join(","), "5,6")
    let result = apply(transform: fn(item): item + offset, value: 2)
    try expect_equal(result, 5)
    try expect_equal(chain(second: fn(item): item + 2, first: fn(): 3), 5)
    let callback = Callback(fn(item: Int): item + 1)
    try expect_equal(callback.transform(3), 4)
    let view = Read(Box(7))
    try expect_equal(view.get(), 7)
    try expect_false(invoke() != 0 or invoke(fn(item): item + 1) != 5)
    let functions: List[fn(value: Int) Int] = [fn(item): item + 4]
    try expect_equal(functions.get(0)(2), 6)
    let nested = fn(value: Int):
        let inner = fn(): "text"
        return value + inner().scalar_length()
    try expect_equal(nested(2), 6)
    let success = with_result(fn(): ok(4))
    try expect_equal(success, Result[Int, TextError].ok(4))
    let propagated = with_result(
        fn():
            let value = try checked()
            return ok(value + 2)
    )
    try expect_equal(propagated, Result[Int, TextError].ok(5))
    let failed = with_result(
        fn():
            if true: return error(TextError("expected"))

            return ok(4)
    )
    try expect_equal(failed, Result[Int, TextError].error(TextError("expected")))
    let subtract: fn(left: Int, right: Int) Int = fn(a, b): a - b
    try expect_equal(subtract(right: 2, left: 7), 5)
    let defaulted: fn(value: Int) Int = fn(item: Int = 4): item + 1
    try expect_equal(defaulted(value: 8), 9)
    let outer: fn(value: Int) fn(input: Int) Int = fn(base):
        return fn(extra): base + extra
    try expect_equal(outer(value: 3)(input: 4), 7)
