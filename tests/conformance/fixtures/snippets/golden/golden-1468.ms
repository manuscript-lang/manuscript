// conform: tags=diagnostics
// conform: phase=check
fn crash(value Int) Int {
	return 1 / value
}

export fn main() Int {
	value := Set[Int]().add(0)
	return value.map(crash).length()
}
// expect-error: MS2001 9:18 unknown or ambiguous member map on Void; this type has no fields or operations
