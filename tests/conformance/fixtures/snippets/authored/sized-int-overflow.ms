// conform: tags=numbers,types,faults,tier-core
// conform: phase=run
// conform: origin=sized numeric types stage 1
import stdout from "@std/io/io.ms"

fn main() Void:
    a Int8 := 100
    void stdout().write("before\n")
    b := a + a
    void stdout().write(f"{b}\n")
