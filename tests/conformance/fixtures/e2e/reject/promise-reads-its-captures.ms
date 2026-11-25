// conform: tags=closures,mutation,diagnostics,tier-stdlib
// conform: phase=check
// A promise that stays in the function reads what it captures: it cannot change the value, and the caller cannot
// change it while the promise is outstanding.
import promise from "@std/concurrency/promise.ms"

fn changes_inside() Void! {
	var xs = ["aaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
	p := promise(() => {
		xs.append("z")
		return ok(1)
	})
	print(p.wait()?)
}

fn changes_outside() Void! {
	var xs = ["aaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
	p := promise(() => ok(xs[0].length()))
	xs.append("b")
	print(p.wait()?)
}
