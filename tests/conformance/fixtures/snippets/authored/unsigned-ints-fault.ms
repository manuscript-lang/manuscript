# conform: tags=numbers,faults,tier-core
# conform: phase=run
# conform: origin=unsigned integer types stage 1
import stdout from "@std/io.ms"

export fn main() Int:
    let a: UInt8 = 5
    let b: UInt8 = 6
    let _ = stdout().write("before\n")
    let c = a - b
    let _ = stdout().write("{c}\n")
    return 0
