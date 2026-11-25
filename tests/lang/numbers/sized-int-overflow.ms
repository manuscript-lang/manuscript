// conform: tags=numbers,types,faults,tier-core
// conform: phase=run
// conform: origin=sized numeric types stage 1
import stdout from "@std/io/io.ms"

fn main() Void {
	a Int8 := 100
	void stdout().write("before\n")

	b := a + a
	void stdout().write(f"{b}\n")
}
// expect-exit: 134
// expect-stdout: before
// expect-stderr: Int overflow; the result does not fit the sized integer type's range, so bound the operands or use a wider type
// expect-stderr:   at sized-int-overflow.ms:10 in main
