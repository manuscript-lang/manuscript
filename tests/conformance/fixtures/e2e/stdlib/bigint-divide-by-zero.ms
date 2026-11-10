// conform: tags=stdlib-bigint,faults,tier-stdlib,numbers
// conform: phase=run
import stdout from "@std/io/io.ms"
import from_int from "@std/math/math.ms"

export fn main() Int:
    zero := from_int(0)
    _ := stdout().write((from_int(1) / zero).to_string_radix(10))
    return 0
