# conform: tags=numbers,types,tier-core
# conform: phase=run
# conform: origin=sized numeric types stage 4
import stdout from "@std/io/io.ms"

export fn main() Int:
    let m: Int8 = -128
    let _ = stdout().write("{m.abs()}\n")
    return 0
