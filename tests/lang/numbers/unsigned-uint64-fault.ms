// conform: tags=numbers,faults,tier-core
// conform: phase=run
// conform: origin=unsigned integer types stage 2
import stdout from "@std/io/io.ms"

fn main() Void {
	top UInt64 := 18446744073709551615
	one UInt64 := 1
	void stdout().write("before\n")

	c := top + one
	void stdout().write(f"{c}\n")
}
// expect-exit: 134
// expect-stdout: before
// expect-stderr: Int overflow; the result does not fit the sized integer type's range, so bound the operands or use a wider type
// expect-stderr:   at unsigned-uint64-fault.ms:11 in main
