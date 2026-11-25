// conform: tags=diagnostics
// conform: phase=check
test "bare" {
	return
}

test "unit" {
	return
}

test "fall" {
	x := 1
}
// expect-error: MS3000 12:5 local binding x is never read; remove it, use it, or name it with a leading '_' to ignore it
