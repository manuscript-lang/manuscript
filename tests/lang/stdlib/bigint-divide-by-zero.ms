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
