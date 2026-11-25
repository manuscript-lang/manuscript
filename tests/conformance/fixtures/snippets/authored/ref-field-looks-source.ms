// conform: tags=ownership,records,tier-core
// conform: phase=run
// conform: origin=design/proposals/borrowed-fields-and-looks.md
type Cursor {
	items &List[String]
	at Int
}

fn total(c Cursor) Int {
	return c.items.length() + c.at
}

fn main() Void {
	var names = ["a", "b"]
	c := Cursor(names, 1)
	print(total(c))
	names.append("c")
	print(names.length())
}
