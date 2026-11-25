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
