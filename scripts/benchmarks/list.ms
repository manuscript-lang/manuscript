import panic from "@std/faults.ms"
export fn main() -> Int:
    let values = [1, 2, 3, 4, 5, 6, 7, 8]
    var i = 0
    var sum = 0
    while i < 5000000:
        sum = sum + values.at(i % 8).unwrap()
        i = i + 1
    if sum != 22500000: return panic("list checksum")
    return 0
