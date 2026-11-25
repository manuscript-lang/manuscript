// conform: tags=diagnostics
// conform: phase=check
export fn value() Int {
	unused := 1
	return 2
}
// expect-error: MS3000 4:5 local binding unused is never read; remove it, use it, or name it with a leading '_' to ignore it
