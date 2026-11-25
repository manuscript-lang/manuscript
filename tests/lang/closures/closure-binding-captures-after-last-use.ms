// conform: tags=closures,mutation,tier-stdlib
// conform: phase=run
// The captured variable changes again once the closure is no longer used, and a closure that changes its capture
// shares the variable.
import stdout from "@std/io/io.ms"

fn main() Void! {
	var xs = [1, 2, 3]
	size := () => xs.length()
	before := size()
	xs.append(4)
	size2 := () => xs.length()
	var n = 1
	bump := () => {
		n += 1
	}
	bump()
	bump()
	stdout().write(f"{before} {size2()} {n}\n")?
}
