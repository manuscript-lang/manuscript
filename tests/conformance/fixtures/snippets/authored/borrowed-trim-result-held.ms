// conform: tags=ownership
// conform: phase=run
// A trimmed text is a view: a `hold` function passes it on and `.clone()` keeps a copy.
fn inner(hold text String) &String {
	return text.trim()
}

fn kept(text String) String {
	return text.trim_start().clone()
}

fn piece(hold text String) &String {
	parts := text.split(",").collect()
	return parts[1].trim_end()
}

fn main() Void {
	print(inner("  padded  "))
	print(kept("  left"))
	print(piece("a, b ,c"))
}
