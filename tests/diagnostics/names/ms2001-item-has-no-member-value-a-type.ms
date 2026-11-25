// conform: tags=diagnostics
// conform: phase=check
type Item {
	value Int
}

fn use(value Item?) Int {
	match value {
		item => return Item.value
		null => return 0
	}
}
// expect-error: MS2001 9:29 Item has no member value; a type name is followed only by an enum case
