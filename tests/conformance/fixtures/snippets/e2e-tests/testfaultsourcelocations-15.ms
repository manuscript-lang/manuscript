// conform: tags=faults,optional,tier-core
// conform: phase=run
// conform: origin=tests/e2e/fault_locations_test.go:130 TestFaultSourceLocations
fn crash(value Int) Int? {
	return (1 / value)
}

export fn main() Int {
	value Int? := 0
	if value != null { return crash(value) or 1 }

	return 0
}
