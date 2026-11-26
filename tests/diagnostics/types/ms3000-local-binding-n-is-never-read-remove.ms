// conform: tags=diagnostics
// conform: phase=check
test "valid" {
	n := 1
}
// expect-error: MS3000 4:5 local binding n is never read; remove it, use it, or name it with a leading '_' to ignore it
