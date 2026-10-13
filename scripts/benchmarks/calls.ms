import panic from "@std/faults.ms"
fn add(a: Int, b: Int) -> Int: a + b
export fn main() -> Int:
    var i = 0
    var sum = 0
    while i < 5000000:
        sum = add(a: sum, b: i)
        i = i + 1
    if sum != 12499997500000: return panic("calls checksum")
    return 0
