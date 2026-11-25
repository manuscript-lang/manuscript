// conform: tags=ownership,tier-core
// conform: phase=check
// A binding made from a bare name views that value; handing the name to a `move`
// parameter ends the value, so the binding cannot be read afterwards. Clone it, or
// finish with it first.
fn eat(move text String) Int {
	return text.length()
}

export fn main() Int {
	var source = f"value{4}"
	view := source
	count := eat(source)
	print(view)
	return count
}
// expect-error: MS3000 13:18 cannot move `source` while `view` borrows it (binding of a part of it, at 12:5); finish using `view` before this, or give `view` its own value by ending its initializer with `.clone()`
