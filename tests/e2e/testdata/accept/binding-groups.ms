import panic from "@std/faults.ms"

let (
    LOW = 1
    HIGH: Int = LOW + 9
)
export let (
    LABEL = "range {LOW}..{HIGH}"
)

test "a constant group declares each constant":
    if not (HIGH == 10 and LABEL == "range 1..10"):
        return panic("check failed")

test "a var group declares mutable locals":
    var (
        total = 0
        step = fn(value: Int) Int:
            return value + 1
    )
    total = step(total)
    if not (total == 1):
        return panic("check failed")

test "a let group declares immutable locals":
    let (
        name = "Ada"
        [first, second] = [1, 2]
    )
    if not (name == "Ada" and first + second == 3):
        return panic("check failed")
