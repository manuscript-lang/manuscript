// conform: tags=testing,tier-core
// conform: phase=check
// `or_else` takes its receiver, and a lent slice is not its to give.
export fn main() Void! {
	var xs = [1, 2, 3, 4]
	ys := xs.slice(0, 2).or_else(e => ok([]))
	xs.append(5)
	print(ys)
}
// expect-error: MS3000 6:14 `slice` borrows `xs`, which this position would keep; store `.clone()` of it, or use it in place
// expect-error: MS3000 7:5 cannot change `xs` while `ys` borrows it (binding of a part of it, at 6:5); finish using `ys` before this, or give `ys` its own value by ending its initializer with `.clone()`
