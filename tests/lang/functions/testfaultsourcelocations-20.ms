// conform: tags=formatter,functions,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:162 TestFaultSourceLocations
fn divide(value Int = 1 / "".length()) Int {
	return value
}

export fn main() Int {
	return divide()
}
// expect-exit: 134
// expect-stderr: division by zero; right must be nonzero, found 0
// expect-stderr:   at testfaultsourcelocations-20.ms:4 in divide
// expect-stderr:   at testfaultsourcelocations-20.ms:9 in main
