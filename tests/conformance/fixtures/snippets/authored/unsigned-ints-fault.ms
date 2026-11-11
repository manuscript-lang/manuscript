// conform: tags=numbers,faults,tier-core
// conform: phase=run
// conform: origin=unsigned integer types stage 1
import stdout from "@std/io/io.ms"

fn main() Unit:
    a: UInt8 := 5
    b: UInt8 := 6
    _ := stdout().write("before\n")
    c := a - b
    _ := stdout().write("{c}\n")
