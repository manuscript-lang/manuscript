// conform: tags=mutation,diagnostics,tier-core
// conform: phase=check
// A result that may be any of two held arguments keeps both unchangeable, not only the first.
fn pick(hold a String, hold b String, first Bool) &String {
	if first {
		return a
	}
	return b
}

fn main() Void {
	var s = "hello"
	var t = "world"
	r := pick(s, t, true)
	t = "changed"
	print(r)
}
// expect-error: MS3000 15:5 cannot reassign `t` while `r` borrows it (binding of a part of it, at 14:5); finish using `r` before this, or give `r` its own value by ending its initializer with `.clone()`
