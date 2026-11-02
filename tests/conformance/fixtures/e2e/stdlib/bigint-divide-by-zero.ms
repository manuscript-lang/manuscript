# conform: tags=stdlib-bigint,faults,tier-stdlib,numbers
# conform: phase=run
import stdout from "@std/io/io.ms"
import from_int from "@std/math/math.ms"

export fn main() Int:
    let zero = from_int(0)
    let _ = stdout().write((from_int(1) / zero).to_string_radix(10))
    return 0
