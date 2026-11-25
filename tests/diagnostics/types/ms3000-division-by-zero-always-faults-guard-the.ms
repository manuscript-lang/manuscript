// conform: tags=diagnostics
// conform: phase=check
fn crash() Int {
	return 1 / 0
}

export fn main() Int {
	values := Map[Int, Int]()
	return values.add(crash(), 1).length()
}
// expect-error: MS3000 4:14 division by zero always faults; guard the divisor or use a nonzero constant
// expect-error: MS2001 9:35 unknown or ambiguous member length on Void; this type has no fields or operations
