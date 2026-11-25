// conform: tags=numbers,faults,tier-core
// conform: phase=run
// conform: origin=unsigned integer types stage 1
import stdout from "@std/io/io.ms"

fn main() Void {
	a UInt8 := 5
	b UInt8 := 6
	void stdout().write("before\n")

	c := a - b
	void stdout().write(f"{c}\n")
}
// expect-exit: 134
// expect-stdout: before
// expect-stderr: Int overflow; the result does not fit the sized integer type's range, so bound the operands or use a wider type
// expect-stderr:   at unsigned-ints-fault.ms:11 in main
