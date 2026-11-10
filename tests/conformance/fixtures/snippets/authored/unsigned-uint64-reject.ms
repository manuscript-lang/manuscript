// conform: tags=numbers,types,tier-core
// conform: phase=check
// conform: origin=unsigned integer types stage 2
export fn main() Int:
    too_big: UInt64 = 18446744073709551616
    negative: UInt64 = -1
    mixed: UInt64 = 5
    n: Int = 3
    sum := mixed + n
    flipped := -mixed
    return 0
