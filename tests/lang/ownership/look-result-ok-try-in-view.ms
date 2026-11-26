// conform: tags=ownership,try-result
// conform: phase=run
fn r(hold s String) &String! {
	if s.length() == 0 {
		return error(Error("empty"))
	}
	return ok(s)
}

fn pick(hold a String) &String! {
	return ok(r(a)?)
}

fn main() Void! {
	a := "kept"
	b := pick(a)?
	print(b)
	blank := ""
	print(pick(blank).is_error().to_string())
}
// expect-exit: 0
// expect-stdout: kept
// expect-stdout: true
