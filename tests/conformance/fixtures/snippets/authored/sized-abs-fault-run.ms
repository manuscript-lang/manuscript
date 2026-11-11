// conform: tags=numbers,types,tier-core
// conform: phase=run
// conform: origin=sized numeric types stage 4
import stdout from "@std/io/io.ms"

fn main() Unit:
    m: Int8 := -128
    _ := stdout().write("{m.abs()}\n")
