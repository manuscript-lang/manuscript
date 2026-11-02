# conform: tags=numbers,faults,tier-core
# conform: phase=run
# conform: origin=unsigned integer types stage 2
import stdout from "@std/io/io.ms"

export fn main() Int:
    let top: UInt64 = 18446744073709551615
    let one: UInt64 = 1
    let _ = stdout().write("before\n")
    let c = top + one
    let _ = stdout().write("{c}\n")
    return 0
