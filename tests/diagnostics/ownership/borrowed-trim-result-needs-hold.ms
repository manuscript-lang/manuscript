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
// expect-error: MS3000 5:1 the result is a part of `text`, so the signature must say `hold` for it; write `hold` before it, or return a `.clone()`
// expect-error: MS3000 9:1 the result is a part of `values`, so the signature must say `hold` for it; write `hold` before it, or return a `.clone()`
// expect-error: MS3000 13:1 the result is a part of `text`, so the signature must say `hold` for it; write `hold` before it, or return a `.clone()`
