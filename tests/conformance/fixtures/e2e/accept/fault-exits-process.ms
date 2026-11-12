// conform: tags=faults,tier-io
// conform: phase=run
import stdout from "@std/io/io.ms"
import panic from "@std/core.ms"

fn checked(n: Int) Int:
	if n > 1: panic("n too large: {n}")
	return n

fn main() Unit:
	_ := stdout().write("before\n")
	_ := stdout().write("{checked(1)}\n")
	_ := stdout().write("{checked(2)}\n")
	_ := stdout().write("unreachable\n")
