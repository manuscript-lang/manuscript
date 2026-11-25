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
