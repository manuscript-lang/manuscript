import {expect_equal, expect_true} from "@std/testing.ms"
import abs_int from "@std/math.ms"
import Scheduler from "@std/tasks.ms"
import Synchronized from "@std/sync.ms"

fn increment(value: Int) Int:
    return value + 1

fn identity[T](value: T) T:
    return value

fn sum(values: List[Int]) Int:
    var total = 0
    for value in values:
        total = total + value
    return total

fn apply(transform: fn(value: Int) Int) Int:
    return transform(4)

fn select() fn(value: Int) Int:
    return increment

fn subtract(amount: Int, deduction: Int) Int:
    return amount - deduction

interface Increment:
    fn apply(value: Int) Int

type Offset:
    delta: Int

impl Increment for Offset:
    fn apply(value: Int) Int:
        return value + self.delta

fn next(state: Synchronized[Int]) Int:
    with locked = state.lock():
        let value = locked.get()
        locked.set(value + 1)
        return value

fn prepare_receiver(state: Synchronized[Int]) Result[Offset, Error]:
    next(state) | try expect_equal(expected: 0)
    return ok(Offset(2))

fn prepare_function(state: Synchronized[Int]) Result[fn(value: Int) Int, Error]:
    next(state) | try expect_equal(expected: 4)
    return ok(increment)

fn absent(value: Optional[Int]) Bool:
    let missing: Optional[Int] = none
    return value == missing

test "optional labels on single-parameter functions":
    increment(3) | try expect_equal(expected: increment(value: 3))
    let multiline = increment(3)
    multiline | try expect_equal(expected: 4)
    identity(7) | try expect_equal(expected: 7)
    identity[Int](7) | try expect_equal(expected: 7)
    (identity(true)) | try expect_true
    identity(unit) | try expect_equal(expected: unit)
    (absent(none)) | try expect_true
    "{increment(3)}" | try expect_equal(expected: "4")
    select()(5) | try expect_equal(expected: 6)
    let specialized = identity[Int]
    specialized(8) | try expect_equal(expected: 8)
    let closure = fn(value: Int):
        return value * 2
    closure(3) | try expect_equal(expected: 6)
    apply(closure) | try expect_equal(expected: 8)
    let result = apply(
        fn(value):
            return value + 2
    )
    result | try expect_equal(expected: 6)
    subtract(deduction: increment(1), amount: increment(8)) | try expect_equal(
        expected: 7
    )

test "optional labels on methods and native functions":
    let offset = Offset(3)
    offset.apply(4) | try expect_equal(expected: 7)
    let view = Increment(offset)
    view.apply(4) | try expect_equal(expected: 7)
    let method = view.apply
    method(5) | try expect_equal(expected: 8)
    abs_int(-3) | try expect_equal(expected: 3)
    let native = abs_int
    native(-4) | try expect_equal(expected: 4)
    sum([]) | try expect_equal(expected: 0)
    sum([1, 2, 3]) | try expect_equal(expected: 6)
    ([1, 2, 3]).reverse_in_place() | try expect_equal(expected: [3, 2, 1])
    [1, 2].append(3) | try expect_equal(expected: [1, 2, 3])
    let lookup = [4, 5].get
    lookup(1) | try expect_equal(expected: 5)
    [4, 5].get(0) | try expect_equal(expected: 4)

    with service = Scheduler(limit: 1, drain: 2.seconds):
        let operation = fn() Result[Unit, Error]:
            return ok(unit)

        match service.start(operation):
            ok(_):
                ((true) | try expect_true)
            error(_):
                ((false) | try expect_true)

test "omitted labels preserve evaluation order":
    let state = Synchronized(0)
    (try prepare_receiver(state)).apply(next(state)) | try expect_equal(expected: 3)
    with locked = state.lock():
        locked.get() | try expect_equal(expected: 2)
    subtract(deduction: next(state), amount: next(state)) | try expect_equal(
        expected: 1
    )
    with locked = state.lock():
        locked.get() | try expect_equal(expected: 4)
    (try prepare_function(state))(next(state)) | try expect_equal(expected: 6)
    with locked = state.lock():
        locked.get() | try expect_equal(expected: 6)
    sum([next(state), next(state)]) | try expect_equal(expected: 13)
    with locked = state.lock():
        locked.get() | try expect_equal(expected: 8)
