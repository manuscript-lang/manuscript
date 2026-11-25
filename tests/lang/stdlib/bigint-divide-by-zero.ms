// conform: tags=stdlib-bigint,faults,tier-stdlib,numbers
// conform: phase=run
import (
	stdout from "@std/io/io.ms",
	big_int_of_int from "@std/math/math.ms",
)

fn main() Void {
	zero := big_int_of_int(0)
	void stdout().write((big_int_of_int(1) / zero).to_string())
}
// expect-exit: 134
// expect-stderr: BigInt./: division by zero; right must be nonzero, found 0
// expect-stderr:   at bigint-divide-by-zero.ms:10 in main
