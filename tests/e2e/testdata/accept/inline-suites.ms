import panic from "@std/faults.ms"

fn double(value: Int) -> Int: return value * 2
fn apply(value: Int, transform: fn(value: Int) -> Int) -> Int: return transform(value)
fn choose(value: Int) -> Int:
    if value > 0: return double(value)
    else: return 0

fn alternate(value: Int) -> Int:
    if value < 0: return -1
    else if value == 0: return 0
    else:
        return 1

test "inline functions and branches":
    if choose(3) != 6: return panic("inline branch failed")
    if choose(-3) != 0: return panic("inline else failed")
    if alternate(0) != 0: return panic("inline else if failed")
    if alternate(3) != 1: return panic("mixed branch failed")
    let increment = fn(value: Int) -> Int: return value + 1
    if increment(2) != 3: return panic("inline closure failed")
    let result = apply(value: 4, transform: fn(value: Int) -> Int: return value * 3)
    if result != 12: return panic("inline callback failed")
    var count = 0
    while count < 3: count = count + 1
    if count != 3: return panic("inline assignment failed")

test "inline test": return
