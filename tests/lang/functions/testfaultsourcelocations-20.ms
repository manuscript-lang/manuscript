// conform: tags=formatter,functions,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:162 TestFaultSourceLocations
fn divide(value Int = 1 / "".length()) Int {
	return value
}

export fn main() Int {
	return divide()
}
