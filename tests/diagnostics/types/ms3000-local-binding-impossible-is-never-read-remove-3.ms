// conform: tags=diagnostics
// conform: phase=check
fn divide(value Int, divisor Int) Int {
	return value / divisor
}

test "fault" {
	impossible := divide(value: 3, divisor: 0)
}
// expect-error: MS3000 8:5 local binding impossible is never read; remove it, use it, or name it with a leading '_' to ignore it
