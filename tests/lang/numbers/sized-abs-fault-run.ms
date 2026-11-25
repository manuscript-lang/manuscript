// conform: tags=numbers,types,tier-core
// conform: phase=run
// conform: origin=sized numeric types stage 4
import stdout from "@std/io/io.ms"

fn main() Void {
	m Int8 := -128
	void stdout().write(f"{m.abs()}\n")
}
// expect-exit: 134
// expect-stderr: Int overflow; the result does not fit the sized integer type's range, so bound the operands or use a wider type
// expect-stderr:   at sized-abs-fault-run.ms:8 in main
