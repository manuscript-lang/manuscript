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
// expect-error: MS3000 10:9 this closure is kept by the runtime (a promise), so it only reads what it captures, but it changes `xs`; clone the value inside the closure, or send changes through a pipe to one owner
// expect-error: MS3000 19:5 cannot change `xs` while `p` captures it (closure, at 18:5); finish using `p` before this, or capture a clone: bind `.clone()` of the value first and capture that binding
