// conform: tags=diagnostics,ownership,records,tier-core
// conform: phase=check
// conform: origin=design/proposals/borrowed-fields-and-looks.md
type Cursor {
	items &List[String]
	at Int
}

fn main() Void {
	var names = ["a", "b"]
	c := Cursor(names, 0)
	names.append("c")
	print(c.items.length())
}
// expect-error: MS3000 12:5 cannot change `names` while `c` borrows it (binding of a part of it, at 11:5); finish using `c` before this, or give `c` its own value by ending its initializer with `.clone()`
