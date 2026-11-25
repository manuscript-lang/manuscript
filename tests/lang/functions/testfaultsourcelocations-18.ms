// conform: tags=formatter,functions,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:147 TestFaultSourceLocations
fn zero() Int {
	return 0
}

export fn main() Int {
	return (1 / zero())
}
// expect-exit: 134
// expect-stderr: division by zero; right must be nonzero, found 0
// expect-stderr:   at testfaultsourcelocations-18.ms:9 in main
