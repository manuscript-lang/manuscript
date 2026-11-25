// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
	if true {
		x := [1]
		return 0
	}

	return 1
}
// expect-error: MS3000 5:9 local binding x is never read; remove it, use it, or name it with a leading '_' to ignore it
