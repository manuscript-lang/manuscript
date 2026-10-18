import panic from "@std/faults.ms"
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

fn prepare_receiver(state: Synchronized[Int]) Offset:
    if not (next(state) == 0):
        return panic(message: "check failed")

    return Offset(2)

fn prepare_function(state: Synchronized[Int]) fn(value: Int) Int:
    if not (next(state) == 4):
        return panic(message: "check failed")

    return increment

fn absent(value: Optional[Int]) Bool:
    let missing: Optional[Int] = none
    return value == missing

test "optional labels on single-parameter functions":
    if not (increment(3) == increment(value: 3)):
        return panic(message: "check failed")

    let multiline = increment(3)
    if not (multiline == 4):
        return panic(message: "check failed")
    if not (identity(7) == 7):
        return panic(message: "check failed")
    if not (identity[Int](7) == 7):
        return panic(message: "check failed")
    if not (identity(true)):
        return panic(message: "check failed")
    if not (identity(unit) == unit):
        return panic(message: "check failed")
    if not (absent(none)):
        return panic(message: "check failed")
    if not ("{increment(3)}" == "4"):
        return panic(message: "check failed")
    if not (select()(5) == 6):
        return panic(message: "check failed")

    let specialized = identity[Int]
    if not (specialized(8) == 8):
        return panic(message: "check failed")

    let closure = fn(value: Int):
        return value * 2
    if not (closure(3) == 6):
        return panic(message: "check failed")
    if not (apply(closure) == 8):
        return panic(message: "check failed")

    let result = apply(
        fn(value):
            return value + 2
    )
    if not (result == 6):
        return panic(message: "check failed")
    if not (subtract(deduction: increment(1), amount: increment(8)) == 7):
        return panic(message: "check failed")

test "optional labels on methods and native functions":
    let offset = Offset(3)
    if not (offset.apply(4) == 7):
        return panic(message: "check failed")

    let view = Increment(offset)
    if not (view.apply(4) == 7):
        return panic(message: "check failed")

    let method = view.apply
    if not (method(5) == 8):
        return panic(message: "check failed")
    if not (abs_int(-3) == 3):
        return panic(message: "check failed")

    let native = abs_int
    if not (native(-4) == 4):
        return panic(message: "check failed")
    if not (sum([]) == 0):
        return panic(message: "check failed")
    if not (sum([1, 2, 3]) == 6):
        return panic(message: "check failed")
    if not (([1, 2, 3]).reverse_in_place() == [3, 2, 1]):
        return panic(message: "check failed")
    if not ([1, 2].append(3) == [1, 2, 3]):
        return panic(message: "check failed")

    let lookup = [4, 5].at
    let expected: Optional[Int] = some(5)
    if not (lookup(1) == expected):
        return panic(message: "check failed")
    if not ([4, 5].at(0) == some(4)):
        return panic(message: "check failed")

    with service = Scheduler(limit: 1, drain: 2.seconds):
        let operation = fn() Result[Unit, Error]:
            return ok(unit)

        match service.start(operation):
            ok(_):
                if not (true):
                    return panic(message: "check failed")
            error(_):
                if not (false):
                    return panic(message: "check failed")

test "omitted labels preserve evaluation order":
    let state = Synchronized(0)
    if not (prepare_receiver(state).apply(next(state)) == 3):
        return panic(message: "check failed")

    with locked = state.lock():
        if not (locked.get() == 2):
            return panic(message: "check failed")
    if not (subtract(deduction: next(state), amount: next(state)) == 1):
        return panic(message: "check failed")

    with locked = state.lock():
        if not (locked.get() == 4):
            return panic(message: "check failed")
    if not (prepare_function(state)(next(state)) == 6):
        return panic(message: "check failed")

    with locked = state.lock():
        if not (locked.get() == 6):
            return panic(message: "check failed")
    if not (sum([next(state), next(state)]) == 13):
        return panic(message: "check failed")

    with locked = state.lock():
        if not (locked.get() == 8):
            return panic(message: "check failed")
