// conform: tags=numbers,types,faults,tier-core
// conform: phase=run
// conform: origin=sized numeric types stage 1
import stdout from "@std/io/io.ms"

fn main() Unit:
    a: Int8 := 100
    _ := stdout().write("before\n")
    b := a + a
    _ := stdout().write("{b}\n")
