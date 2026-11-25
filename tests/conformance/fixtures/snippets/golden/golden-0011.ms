// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
	return 0
}

fn g() Int {
	x := 1
	return 2
}
// expect-error: MS3000 8:5 local binding x is never read; remove it, use it, or name it with a leading '_' to ignore it
