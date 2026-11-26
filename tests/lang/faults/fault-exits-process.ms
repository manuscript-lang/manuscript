// conform: tags=faults,tier-io
// conform: phase=run
import (
	panic from "@std/core.ms",
	stdout from "@std/io/io.ms",
)

fn checked(n Int) Int {
	if n > 1 { panic(f"n too large: {n}") }
	return n
}

fn main() Void {
	void stdout().write("before\n")
	void stdout().write(f"{checked(1)}\n")
	void stdout().write(f"{checked(2)}\n")
	void stdout().write("unreachable\n")
}
// expect-exit: 134
// expect-stdout: before
// expect-stdout: 1
// expect-stderr: n too large: 2
// expect-stderr:   at fault-exits-process.ms:9 in checked
// expect-stderr:   at fault-exits-process.ms:16 in main
