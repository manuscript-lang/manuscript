# conform: tags=aliasing,closures,control-flow,generics,interfaces,lists,modules,mutation,optional,records,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/default-arguments.ms
import TextError from "@std/core.ms"
import {expect_equal, expect_false} from "@std/test.ms"

type Cell:
    value: Int

fn increment(value: Int = 3) Int:
    return value + 1

fn combine(first: Int = 2, second: Int, third: Int = first + second) Int:
    return first + second + third

fn identity[T](value: T, fallback: T = value) T:
    return fallback

fn ordered(
    seed: Int,
    first: Int = seed * 10 + 3,
    second: Int = first * 10 + 4,
    third: Int = 0
) Int:
    return second * 10 + 5 + third

fn unit_default() Unit:
    return unit

fn unit_value(value: Unit = unit_default()) Unit:
    return value

fn optional(value: Optional[Int] = some(3)) Optional[Int]:
    return value

fn fail() Result[Int, TextError]:
    return error(TextError("default failure"))

fn propagate(value: Int = try fail()) Result[Int, TextError]:
    return ok(value)

interface Add:
    fn add(value: Int) Int

type Offset:
    value: Int

impl Add for Offset:
    fn add(value: Int = self.value) Int:
        return self.value + value

interface Read[T]:
    fn read(value: T) T

type Box[T]:
    value: T

impl Read[T] for Box[T]:
    fn read(value: T = self.value) T:
        return value

test "omitted and explicit defaults":
    (increment() != 4 or increment(7) != 8 or increment(value: 0) != 1) | try expect_false
    (combine(second: 5) != 14 or combine(third: 0, second: 5, first: 0) != 5) | try expect_false
    (identity(value: 9) != 9 or identity(value: 9, fallback: 4) != 4) | try expect_false
    unit_value(unit) | try expect_equal(unit)
    unit_value() | try expect_equal(unit)
    (optional(value: none) != Optional[Int].none or optional() != some(3)) | try expect_false
    (
        (
            propagate() != Result[Int, TextError].error(
                TextError("default failure")
            )
            or propagate(7) != Result[Int, TextError].ok(7)
        )
    ) | try expect_false

test "default evaluation order and repeated calls":
    ordered(0) | try expect_equal(345)
    ordered(0, third: 1) | try expect_equal(346)
    ordered(0, second: 7) | try expect_equal(75)
    ordered(1, first: 2) | try expect_equal(245)
    ordered(0) | try expect_equal(345)

test "function values and captures":
    let copy = increment
    let copied = copy
    copied() | try expect_equal(4)

    let typed: fn(Int) Int = increment
    typed(2) | try expect_equal(3)

    let offset = 5
    let callback = fn(value: Int = offset):
        return value
    (callback() != 5 or callback(0) != 0) | try expect_false

    let nested = fn(first: Int = 6, second: Int = first + 1):
        return second
    nested() | try expect_equal(7)

test "implementation and bound method defaults":
    let offset = Offset(4)
    let bound = offset.add
    (offset.add() != 8 or bound() != 8 or bound(0) != 4) | try expect_false

    let view = Add(offset)
    view.add(2) | try expect_equal(6)

    let box = Box[String]("boxed")
    box.read() | try expect_equal("boxed")
