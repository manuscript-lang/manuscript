// conform: tags=faults,modules,stdlib-errors,tier-stdlib,try-result
// conform: phase=run
// conform: origin=tests/e2e/fault_locations_test.go:104 TestFaultSourceLocations

fn crash(value Int) Int {
	return 1 / value
}

export fn main() Int {
	value Int!Error := ok(0)
	return value.map(crash).get()
}
// expect-exit: 134
// expect-stderr: division by zero; right must be nonzero, found 0
// expect-stderr:   at testfaultsourcelocations-11.ms:6 in crash
// expect-stderr:   at @std/core.ms:<LINE> in Result.map
// expect-stderr:   at testfaultsourcelocations-11.ms:11 in main
