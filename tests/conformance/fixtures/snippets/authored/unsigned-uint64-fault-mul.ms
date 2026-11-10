// conform: tags=numbers,faults,tier-core
// conform: phase=run
// conform: origin=unsigned integer types UInt64 inline checks

import stdout from "@std/io/io.ms"

fn main() Unit:
    top: UInt64 = 18446744073709551615
    one: UInt64 = 1
    _ := stdout().write("before\n")
    c := top * top
    _ := stdout().write("{c}\n")
