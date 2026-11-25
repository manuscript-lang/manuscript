// conform: tags=closures,formatter,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:167 TestFaultSourceLocations
export fn main() Int {
	crash := fn() Int {
		return 1 / "".length()
	}
	return crash()
}
// expect-exit: 134
// expect-stderr: division by zero; right must be nonzero, found 0
// expect-stderr:   at testfaultsourcelocations-21.ms:6 in main.closure
// expect-stderr:   at testfaultsourcelocations-21.ms:8 in main
