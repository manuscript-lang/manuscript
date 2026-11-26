// conform: tags=faults,formatter,optional,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:130 TestFaultSourceLocations
fn crash(value Int) Int? {
	return (1 / value)
}

export fn main() Int {
	value Int? := 0
	if value != null { return crash(value) or 1 }

	return 0
}
// expect-exit: 134
// expect-stderr: division by zero; right must be nonzero, found 0
// expect-stderr:   at testfaultsourcelocations-15.ms:5 in crash
// expect-stderr:   at testfaultsourcelocations-15.ms:10 in main
