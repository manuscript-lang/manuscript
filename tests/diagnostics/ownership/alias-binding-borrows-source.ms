// conform: tags=ownership,mutation,diagnostics,tier-core
// conform: phase=check
// A name bound from another name that stays in use borrows it: the source cannot change while the alias is read
// (the append can move the list's storage out from under it).
export fn main() Int {
	var xs = ["hello"]
	ys := xs
	for i in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16] {
		xs.append(f"item{i}")
	}
	return ys[0].length() + ys.length()
}
// expect-error: MS3000 9:9 cannot change `xs` while `ys` borrows it (binding of a part of it, at 7:5); finish using `ys` before this, or give `ys` its own value by ending its initializer with `.clone()`
