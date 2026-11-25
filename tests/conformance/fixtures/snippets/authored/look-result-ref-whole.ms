// conform: tags=ownership,try-result
// conform: phase=run
type Bad {
	why String
}

type Row {
	name String
}

fn relay(hold result Row!Bad) &Row!Bad {
	return result
}

fn main() Void {
	r := relay(ok(Row("x")))
	print(r.is_error())
}
