// conform: tags=closures,mutation,tier-stdlib
// conform: phase=run
// A value a promise read can change again once the promise is waited on.
import promise from "@std/concurrency/promise.ms"
import stdout from "@std/io/io.ms"

fn main() Void! {
	var xs = ["aaaa"]
	p := promise(() => ok(xs[0].length()))
	n := p.wait()?
	xs.append("b")
	stdout().write(f"{n} {xs.length()}\n")?
}
