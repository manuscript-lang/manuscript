// conform: tags=ownership
// conform: phase=check
// `trim` borrows its receiver, so a function that returns a trimmed text, a trimmed map value, or
// a trimmed piece of a split must say `hold`, or return `.clone()`.
fn direct(text String) String {
	return text.trim()
}

fn of_map(values Map[String, String]) String {
	return values["key"].trim()
}

fn of_piece(text String) String {
	parts := text.split(",")
	return parts[0].trim()
}

fn main() Void {
	print(direct(" a "))
}
