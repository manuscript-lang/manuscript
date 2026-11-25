// conform: tags=diagnostics
// conform: phase=check
fn label(value Int) String {
	return f"{value}"
}

test "methods" {
	labels := [1].map(transform: label)
	convert := [2].map[String]
	text := " hello ".trim()
}
// expect-error: MS3000 8:5 local binding labels is never read; remove it, use it, or name it with a leading '_' to ignore it
// expect-error: MS3000 9:5 local binding convert is never read; remove it, use it, or name it with a leading '_' to ignore it
// expect-error: MS3000 10:5 local binding text is never read; remove it, use it, or name it with a leading '_' to ignore it
