// conform: tags=testing,tier-core
// conform: phase=check
// A view borrows its receiver: changing the receiver while the view is still used is
// rejected.
export fn main() Int {
	var text = "hello world"
	word := text.view(0, 5)
	text = "other"
	return word.length()
}
// expect-error: MS3000 8:5 cannot reassign `text` while `word` borrows it (binding of a part of it, at 7:5); finish using `word` before this, or give `word` its own value by ending its initializer with `.clone()`
