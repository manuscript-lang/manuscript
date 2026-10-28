from "@std/core.ms" import panic

export def main() -> Int:
    let values = [1, 2, 3, 4, 5, 6, 7, 8]
    var sum = 0
    for i in 0..5000000:
        sum += values.get(i % 8)
    if sum != 22500000: return panic("list checksum")

    return 0
