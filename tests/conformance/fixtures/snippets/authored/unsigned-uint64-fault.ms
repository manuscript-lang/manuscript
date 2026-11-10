// conform: tags=numbers,faults,tier-core
// conform: phase=run
// conform: origin=unsigned integer types stage 2
import stdout from "@std/io/io.ms"

export fn main() Int:
    top: UInt64 = 18446744073709551615
    one: UInt64 = 1
    _ := stdout().write("before\n")
    c := top + one
    _ := stdout().write("{c}\n")
    return 0
