// conform: tags=formatter,functions,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:153 TestFaultSourceLocations
fn divide(value Int) Int {
	return 1 / value
}

fn outer(value Int) Int {
	return value
}

export fn main() Int {
	return outer(divide(0))
}
// expect-exit: 134
// expect-stderr: division by zero; right must be nonzero, found 0
// expect-stderr:   at testfaultsourcelocations-19.ms:5 in divide
// expect-stderr:   at testfaultsourcelocations-19.ms:13 in main
