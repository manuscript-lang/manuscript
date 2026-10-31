# conform: tags=numbers,faults,tier-core
# conform: phase=run
# conform: origin=unsigned integer types UInt64 inline checks

import stdout from "@std/io.ms"

export fn main() Int:
    let top: UInt64 = 18446744073709551615
    let one: UInt64 = 1
    let _ = stdout().write("before\n")
    let c = top * top
    let _ = stdout().write("{c}\n")
    return 0
