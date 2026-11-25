// conform: tags=diagnostics
// conform: phase=check
type P {
	x Int
}

fn f(p P) Int {
	return p.y
}
// expect-error: MS2001 8:14 unknown or ambiguous member y on P; available: x
