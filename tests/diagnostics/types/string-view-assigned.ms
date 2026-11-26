// conform: tags=testing,tier-core
// conform: phase=check
// A native view assigned to a field or an owning `var` is kept by it: `.clone()` keeps the text.
type Label {
	name String
}

export fn main() Int {
	var label = Label("  hello  ")
	var text = "  world  "
	label.name = label.name.trim()
	text = text.trim()
	return label.name.length() + text.length()
}
// expect-error: MS3000 11:29 `trim` borrows `label.name`, which this position would keep; store `.clone()` of it, or use it in place
// expect-error: MS3000 12:17 `trim` borrows `text`, which this position would keep; store `.clone()` of it, or use it in place
