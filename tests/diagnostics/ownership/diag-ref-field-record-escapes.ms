// conform: tags=diagnostics,ownership,records,tier-core
// conform: phase=check
// conform: origin=design/proposals/borrowed-fields-and-looks.md
type Cursor {
	items &List[String]
	at Int
}

type Holder {
	cursor Cursor
}

fn make(names List[String]) Cursor {
	return Cursor(names, 0)
}

fn keep(hold names List[String]) Holder {
	return Holder(Cursor(names, 0))
}

fn copy(hold names List[String]) Cursor {
	c := Cursor(names, 0)
	return c.clone()
}
// expect-error: MS3000 13:1 a `&` result points into an argument; mark that argument `hold`, or return an owned value
// expect-error: MS3000 21:1 a `&` result must be a part of a `hold` argument, but this body returns a new value; remove the `&` or return a part of the held argument
// expect-error: MS3000 23:14 a value with a `&` field looks at another value, so it has no copy of its own; clone the part you need, such as its items
