// conform: tags=closures,mutation,diagnostics,tier-core
// conform: phase=check
// Calling a closure that changes a captured list changes the list: another closure that reads it and is used later
// would see a stale copy (the append can move the storage).
fn main() Void {
	var xs = ["hello"]
	grow := () => {
		for i in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16] {
			xs.append(f"item{i}")
		}
	}
	size := () => xs[0].length() + xs.length()
	grow()
	print(f"{size()}")
}
// expect-error: MS3000 13:5 cannot change `xs` while `size` captures it (closure, at 12:5); finish using `size` before this, or capture a clone: bind `.clone()` of the value first and capture that binding
