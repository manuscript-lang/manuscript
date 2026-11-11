// conform: tags=testing,tier-core
// conform: phase=check
// A returned `String` is owned, but `view` only borrows its receiver, so returning one
// (of a local or of a parameter) is rejected; copy it with `.clone()` after the view.
fn result() String:
	text := "hello world"
	return text.view(1, 5)

export fn main() Int:
	return result().length()
