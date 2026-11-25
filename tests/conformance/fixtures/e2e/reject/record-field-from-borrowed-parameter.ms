// conform: tags=ownership,tier-core
// conform: phase=check
// A borrowed parameter handed to a record constructor is copied unless the source says
// `.clone()` or the parameter is `move`.
type Box {
	items List[Int]
}

fn wrap(xs List[Int]) Box {
	return Box(xs)
}

fn main() Void {
	print(wrap([1, 2]).items.length())
}
// expect-error: MS3000 10:16 `xs` is a view of another value, not an owner, and cannot be moved here; take the owner with `move`, or pass `xs.clone()`
