// conform: tags=numbers,faults,tier-core
// conform: phase=run
// conform: origin=unsigned integer types UInt64 inline checks

import stdout from "@std/io/io.ms"

fn main() Void:
    top UInt64 := 18446744073709551615
    one UInt64 := 1
    void stdout().write("before\n")
    c := one - top
    void stdout().write(f"{c}\n")
