import {expect_equal, expect_false} from "@std/testing.ms"
import {Synchronized, SynchronizedGuard} from "@std/sync.ms"

fn increment(value: Int = 3) -> Int:
    return value + 1

fn combine(first: Int = 2, second: Int, third: Int = first + second) -> Int:
    return first + second + third

fn identity[T](value: T, fallback: T = value) -> T:
    return fallback

fn mark(state: SynchronizedGuard[Int], value: Int) -> Int:
    state.set(value: state.get() * 10 + value)
    return value

fn ordered(
    state: SynchronizedGuard[Int],
    first: Int = mark(state: state, value: 3),
    second: Int = mark(state: state, value: 4),
    third: Int = 0
) -> Int:
    state.set(value: state.get() * 10 + 5)
    return first + second + third

fn unit_default(calls: List[Int]) -> Unit:
    calls.append(1)

fn unit_value(calls: List[Int], value: Unit = unit_default(calls)) -> Unit:
    return value

fn optional(value: Optional[Int] = some(3)) -> Optional[Int]:
    return value

fn fail() -> Result[Int, String]:
    return error("default failure")

fn propagate(value: Int = try fail()) -> Result[Int, String]:
    return ok(value)

interface Add:
    fn add(value: Int) -> Int

type Offset:
    value: Int

impl Add for Offset:
    fn add(value: Int = self.value) -> Int:
        return self.value + value

interface Read[T]:
    fn read(value: T) -> T

type Box[T]:
    value: T

impl Read[T] for Box[T]:
    fn read(value: T = self.value) -> T:
        return value

test "omitted and explicit defaults":
    (increment() != 4 or increment(7) != 8 or increment(value: 0) != 1) | try expect_false
    (combine(second: 5) != 14 or combine(third: 0, second: 5, first: 0) != 5) | try expect_false
    (identity(value: 9) != 9 or identity(value: 9, fallback: 4) != 4) | try expect_false
    let calls: List[Int] = []
    unit_value(calls, unit)
    calls.length() | try expect_equal(expected: 0)
    (optional(value: none) != Optional[Int].none or optional() != some(3)) | try expect_false
    (
        (
            propagate() != Result[Int, String].error("default failure")
            or propagate(7) != Result[Int, String].ok(7)
        )
    ) | try expect_false

test "default evaluation order and repeated calls":
    let counter = Synchronized[Int](0)

    with state = counter.lock():
        let total = ordered(
            state: state,
            third: mark(state: state, value: 1),
            second: mark(state: state, value: 2)
        )
        (total != 6 or state.get() != 1235) | try expect_false
        state.set(value: 0)
        let ignored = ordered(state: state)
        state.get() | try expect_equal(expected: 345)
        state.set(value: 0)
        let again = ordered(state: state)
        state.get() | try expect_equal(expected: 345)

test "function values and captures":
    let copy = increment
    let copied = copy
    copied() | try expect_equal(expected: 4)
    let typed: fn(value: Int) -> Int = increment
    typed(2) | try expect_equal(expected: 3)
    var offset = 5
    let callback = fn(value: Int = offset):
        return value
    offset = 9
    (callback() != 5 or callback(0) != 0) | try expect_false
    let nested = fn(first: Int = 6, second: Int = first + 1):
        return second
    nested() | try expect_equal(expected: 7)

test "implementation and bound method defaults":
    let offset = Offset(4)
    let bound = offset.add
    (offset.add() != 8 or bound() != 8 or bound(0) != 4) | try expect_false
    let view = Add(offset)
    view.add(2) | try expect_equal(expected: 6)
    let box = Box[String]("boxed")
    box.read() | try expect_equal(expected: "boxed")
