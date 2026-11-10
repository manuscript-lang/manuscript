// conform: tags=numbers,faults,stdlib-math,tier-stdlib
// conform: phase=run
// conform: origin=shift counts are checked in math.ms
import shift_left from "@std/math/math.ms"

export fn main() Int:
    count := 64
    print(shift_left(1, count))
    return 0
