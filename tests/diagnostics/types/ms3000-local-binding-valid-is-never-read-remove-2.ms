// conform: tags=diagnostics
// conform: phase=check
test "continues after preconditions" {
	valid := 1
}
// expect-error: MS3000 4:5 local binding valid is never read; remove it, use it, or name it with a leading '_' to ignore it
