// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=foreign-syntax diagnostics
type P {
	n Int = 1
}

fn label(p P) String {
	return "x"
}

fn main() Void {
	p := P()
	print(p.label())
}
// expect-error: MS2001 14:13 unknown or ambiguous member label on P; label is a function here, not a method of P: call it as label(value) with the value as an argument, or declare it as a method with `fn P.label()`
