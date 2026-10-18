import panic from "@std/faults.ms"
import {Synchronized, SynchronizedGuard} from "@std/sync.ms"

fn increment(value: Int = 3) Int:
    return value + 1

fn combine(first: Int = 2, second: Int, third: Int = first + second) Int:
    return first + second + third

fn identity[T](value: T, fallback: T = value) T:
    return fallback

fn mark(state: SynchronizedGuard[Int], value: Int) Int:
    state.set(value: state.get() * 10 + value)
    return value

fn ordered(
    state: SynchronizedGuard[Int],
    first: Int = mark(state, value: 3),
    second: Int = mark(state, value: 4),
    third: Int = 0
) Int:
    state.set(value: state.get() * 10 + 5)
    return first + second + third

fn unit_value(value: Unit = panic("unexpected default")) Unit:
    return value

fn optional(value: Optional[Int] = some(3)) Optional[Int]:
    return value

fn fail() Result[Int, String]:
    return error("default failure")

fn propagate(value: Int = try fail()) Result[Int, String]:
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
    if (increment() != 4 or increment(7) != 8 or increment(value: 0) != 1):
        return panic("single parameter defaults")
    if combine(second: 5) != 14 or combine(third: 0, second: 5, first: 0) != 5:
        return panic("required arguments and dependent defaults")
    if identity(value: 9) != 9 or identity(value: 9, fallback: 4) != 4:
        return panic("generic defaults")

    unit_value(unit)
    if optional(value: none) != Optional[Int].none or optional() != some(3):
        return panic("explicit none must override default")
    if (
        propagate() != Result[Int, String].error("default failure")
        or propagate(7) != Result[Int, String].ok(7)
    ):
        return panic("default propagation belongs to callee")

test "default evaluation order and repeated calls":
    let counter = Synchronized[Int](0)

    with state = counter.lock():
        let total = ordered(
            state,
            third: mark(state, value: 1),
            second: mark(state, value: 2)
        )
        if total != 6 or state.get() != 1235:
            return panic("supplied arguments precede defaults and body")

        state.set(value: 0)
        ordered(state)
        if state.get() != 345:
            return panic("defaults evaluate in declaration order")

        state.set(value: 0)
        ordered(state)
        if state.get() != 345:
            return panic("defaults run on every call")

test "function values and captures":
    let copy = increment
    let copied = copy
    if copied() != 4:
        return panic("inferred immutable copies retain defaults")

    let typed: fn(value: Int) Int = increment
    if typed(2) != 3:
        return panic("explicit function type remains compatible")

    var offset = 5
    let callback = fn(value: Int = offset):
        return value
    offset = 9
    if callback() != 5 or callback(0) != 0:
        return panic("default expressions capture snapshots")

    let nested = fn(first: Int = 6, second: Int = first + 1):
        return second
    if nested() != 7:
        return panic("anonymous dependent defaults")

test "implementation and bound method defaults":
    let offset = Offset(4)
    let bound = offset.add
    if (offset.add() != 8 or bound() != 8 or bound(0) != 4):
        return panic("receiver defaults")

    let view = Add(offset)
    if view.add(2) != 6:
        return panic("contract view call")

    let box = Box[String]("boxed")
    if box.read() != "boxed":
        return panic("generic method defaults")
