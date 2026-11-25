// conform: tags=ownership,try-result
// conform: phase=run
type Row {
	name String?
}

fn hold Row.name_of() &String?! {
	return ok(self.name)
}

fn hold Row.whole(hold held String?!) &String?! {
	return held
}

fn main() Void! {
	row := Row("n")
	got := row.name_of()?
	if got != null { print(got) }
	print((row.name != null).to_string())
	empty := Row(null)
	none := empty.name_of()?
	print((none == null).to_string())
}
