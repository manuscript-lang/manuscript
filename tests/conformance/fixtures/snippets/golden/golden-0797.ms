// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
	x := (1 + 2)
	return 0
}
// expect-error: MS3000 4:5 local binding x is never read; remove it, use it, or name it with a leading '_' to ignore it
