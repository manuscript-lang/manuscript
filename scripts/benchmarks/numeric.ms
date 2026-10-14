import panic from "@std/faults.ms"
export fn main() -> Int:
    var i = 0
    var sum = 0
    while i < 5000000:
        if i % 100 >= 48: sum = sum + 1
        i = i + 1
    if sum != 2600000: return panic("numeric checksum")
    return 0
