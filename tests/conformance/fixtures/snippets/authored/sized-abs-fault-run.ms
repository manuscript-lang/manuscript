// conform: tags=numbers,types,tier-core
// conform: phase=run
// conform: origin=sized numeric types stage 4
import stdout from "@std/io/io.ms"

fn main() Unit:
    let m: Int8 = -128
    let _ = stdout().write("{m.abs()}\n")
