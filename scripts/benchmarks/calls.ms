import panic from "@std/faults.ms"
import range from "@std/collections.ms"

fn add(a: Int, b: Int) Int: a + b

export fn main() Int:
    var sum = 0
    for i in range(0, 5000000):
        sum = add(a: sum, b: i)
    if sum != 12499997500000: return panic("calls checksum")

    return 0
