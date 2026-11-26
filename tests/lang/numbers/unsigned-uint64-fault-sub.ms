// conform: tags=numbers,faults,tier-core
// conform: phase=run
// conform: origin=unsigned integer types UInt64 inline checks

import stdout from "@std/io/io.ms"

fn main() Void {
	top UInt64 := 18446744073709551615
	one UInt64 := 1
	void stdout().write("before\n")

	c := one - top
	void stdout().write(f"{c}\n")
}
// expect-exit: 134
// expect-stdout: before
// expect-stderr: Int overflow; the result does not fit the sized integer type's range, so bound the operands or use a wider type
// expect-stderr:   at unsigned-uint64-fault-sub.ms:12 in main
