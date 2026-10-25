# conform: tags=stdlib-bigint,faults,tier-stdlib,numbers
# conform: phase=run
from "@std/io.ms" import stdout
from "@std/math.ms" import from_int

export def main() -> Int:
    let zero = from_int(0)
    stdout().write((from_int(1) / zero).to_string_radix(10))
    return 0
