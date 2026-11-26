// conform: tags=stdlib,tier-stdlib
// conform: phase=run
import memory_usage from "@std/os/system.ms"

fn big(n Int) String {
	return "x".repeat(20000000 + n)
}

// A string a statement makes and only reads is freed once its last use is done, also in
// the program entry. `exit_drops` once gated the drop to the end of `main` before
// `lastuse` could move it, so eight 20 MB strings stayed live until the process exited.
fn main() Void {
	before := memory_usage().get().resident
	a := big(1).length()
	b := big(2).length()
	c := big(3).length()
	d := big(4).length()
	e := big(5).length()
	f := big(6).length()
	g := big(7).length()
	h := big(8).length()
	grown := memory_usage().get().resident - before
	print(a + b + c + d + e + f + g + h)
	print(grown < 60000000)
}
