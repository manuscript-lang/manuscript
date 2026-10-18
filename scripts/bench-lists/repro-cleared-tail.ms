import panic from "@std/faults.ms"

export fn main() Int:
    let values = [1, 2, 3]
    var total = 0
    var count = 0

    for value in values:
        total = total + value
        if count == 0:
            values.remove(0)
        count = count + 1

    if total != 7:
        panic("unexpected sum")
    return 0
