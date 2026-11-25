// conform: tags=diagnostics
// conform: phase=check
type Int {
	x Int
}

fn f() Int {
	t := Int(x: 2)
	return 0
}
// expect-error: MS2001 3:1 duplicate or intrinsic name Int; this name is already declared, imported, or built in, so rename one of them
