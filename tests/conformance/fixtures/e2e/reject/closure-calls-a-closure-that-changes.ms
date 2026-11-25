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
