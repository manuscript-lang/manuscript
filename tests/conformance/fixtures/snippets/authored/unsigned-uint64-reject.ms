# conform: tags=numbers,types,tier-core
# conform: phase=check
# conform: origin=unsigned integer types stage 2
export fn main() Int:
    let too_big: UInt64 = 18446744073709551616
    let negative: UInt64 = -1
    let mixed: UInt64 = 5
    let n: Int = 3
    let sum = mixed + n
    let flipped = -mixed
    return 0
