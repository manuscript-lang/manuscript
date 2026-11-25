// conform: tags=faults,formatter,lists,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:87 TestFaultSourceLocations
fn pick(values List[Int], index Int) Int {
	return values[index]
}

export fn main() Int {
	return pick([1, 2, 3], 3)
}
// expect-exit: 134
// expect-stderr: index 3 out of range for length 3; use get_or(index, default) to avoid the fault
// expect-stderr:   at testfaultsourcelocations-8.ms:5 in pick
// expect-stderr:   at testfaultsourcelocations-8.ms:9 in main
