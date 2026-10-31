# conform: tags=numbers,types,faults,tier-core
# conform: phase=run
# conform: origin=sized numeric types stage 1
import stdout from "@std/io.ms"

export fn main() Int:
    let a: Int8 = 100
    let _ = stdout().write("before\n")
    let b = a + a
    let _ = stdout().write("{b}\n")
    return 0
