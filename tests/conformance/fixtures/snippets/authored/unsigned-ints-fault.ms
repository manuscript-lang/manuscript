// conform: tags=numbers,faults,tier-core
// conform: phase=run
// conform: origin=unsigned integer types stage 1
import stdout from "@std/io/io.ms"

fn main() Void:
    a UInt8 := 5
    b UInt8 := 6
    void stdout().write("before\n")
    c := a - b
    void stdout().write(f"{c}\n")
