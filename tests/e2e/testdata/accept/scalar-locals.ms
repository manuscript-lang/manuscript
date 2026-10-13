import List from "@std/collections.ms"
import panic from "@std/faults.ms"

fn sum(limit: Int) -> Int:
    var index = 0
    var total = 0

    while index < limit:
        total = total + index
        index = index + 1

    return total

fn forwarded[T](value: T) -> T:
    let copy = value
    return copy

test "scalar storage retains assignment, shadowing and capture snapshots":
    var number = 3
    let snapshot = fn() -> Int: number
    number = 7
    if snapshot() != 3 or number != 7:
        return panic("capture")

    if true:
        var number = 11
        number = number + 1
        if number != 12:
            return panic("shadow")

    if number != 7 or sum(1024) != 523776:
        return panic("outer")

    let floats = [0.5, 1.5]
    let [first, second] = floats
    var floating = first
    floating = floating * second + 0.25
    if floating != 1.0:
        return panic("float")

    var flag = false
    flag = not flag
    if not flag or forwarded(flag) != true:
        return panic("bool generic")

test "scalar local reads precede mutation and stay in short circuit regions":
    var number = 2
    let compared = number == (
        match some(1):
            some(value):
                number = number + 1
                2
            none: 0
    )
    if not compared or number != 3:
        return panic("ordered equality")

    var touched = false
    let skipped = (
        false
        and (
            match some(1):
                some(value):
                    touched = true
                    true
                none: false
        )
    )
    if skipped or touched:
        return panic("short circuit")

    number = (
        match some(1):
            some(value): 5
            none: 6
    )

    if number != 5:
        return panic("boxed match assignment")
