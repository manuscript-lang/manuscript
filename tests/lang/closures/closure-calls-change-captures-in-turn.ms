// conform: tags=closures,mutation,tier-core
// conform: phase=run
// A closure that changes its capture can be called again, and a reader made after the last change sees the result.
fn main() Void {
	var xs = ["hello"]
	grow := () => {
		xs.append("more")
	}
	grow()
	grow()
	size := () => xs[0].length() + xs.length()
	print(f"{size()}")
}
