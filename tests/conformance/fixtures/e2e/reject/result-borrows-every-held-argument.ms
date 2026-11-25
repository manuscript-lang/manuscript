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
