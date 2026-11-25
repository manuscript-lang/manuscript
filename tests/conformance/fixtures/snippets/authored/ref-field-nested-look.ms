// conform: tags=ownership,records,tier-core
// conform: phase=run
// conform: origin=design/proposals/borrowed-fields-and-looks.md
type Cursor {
	items &List[String]
	at Int
}

type Holder {
	cursor Cursor
	label String
}

fn make(hold names List[String]) Holder {
	return Holder(Cursor(names, 1), "x")
}

fn main() Void {
	names := ["a", "b"]
	h := make(names)
	print(h.cursor.items.length() + h.cursor.at)
	print(h.label)
}
