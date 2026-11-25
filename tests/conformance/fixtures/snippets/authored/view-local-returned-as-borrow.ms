// conform: tags=ownership
// conform: phase=run
// A local bound to a view stays a view when a `hold` function returns it as `&String` or `&String?`.
fn first(hold text String) &String {
	piece := text.view(0, 1)
	return piece
}

fn maybe(hold text String) &String? {
	piece := text.view(1, 3)
	return piece
}

fn main() Void {
	print(first("abc"))
	print(maybe("abcd") or "none")
}
