// conform: tags=closures,mutation,diagnostics,tier-core
// conform: phase=check
// A closure that calls a changing closure changes what that one captured when it runs.
fn main() Void {
	var xs = ["hello"]
	grow := () => {
		xs.append("x")
	}
	again := () => {
		grow()
	}
	size := () => xs.length()
	again()
	print(f"{size()}")
}
// expect-error: MS3000 13:5 cannot change `xs` while `size` captures it (closure, at 12:5); finish using `size` before this, or capture a clone: bind `.clone()` of the value first and capture that binding
