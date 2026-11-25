// conform: tags=testing,tier-core
// conform: phase=check
// `get(default)` on a lent slice returns the payload, still a view into the list. Keeping it
// while the list changes leaves a dangling view, so the checker rejects the change.
export fn main() Int {
	var xs = [1, 2, 3, 4]
	ys := xs.slice(0, 2).get_or([])
	xs.append(5)
	return ys.length()
}
// expect-error: MS3000 8:5 cannot change `xs` while `ys` borrows it (binding of a part of it, at 7:5); finish using `ys` before this, or give `ys` its own value by ending its initializer with `.clone()`
