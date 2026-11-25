// conform: tags=diagnostics
// conform: phase=check
fn sum(value Int) Int {
	return value + 1
}

test "fault" {
	impossible := sum(value: 9223372036854775807)
}
// expect-error: MS3000 8:5 local binding impossible is never read; remove it, use it, or name it with a leading '_' to ignore it
