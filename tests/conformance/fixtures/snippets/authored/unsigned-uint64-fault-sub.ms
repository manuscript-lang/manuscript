// conform: tags=numbers,faults,tier-core
// conform: phase=run
// conform: origin=unsigned integer types UInt64 inline checks

import stdout from "@std/io/io.ms"

fn main() Unit:
    let top: UInt64 = 18446744073709551615
    let one: UInt64 = 1
    let _ = stdout().write("before\n")
    let c = one - top
    let _ = stdout().write("{c}\n")
