// conform: tags=faults,formatter,lists,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:136 TestFaultSourceLocations
fn deep(l List[Int], i Int) Int {
	return l[i]
}

export fn main() Int {
	return deep(l: [1], i: 5)
}
// expect-exit: 134
// expect-stderr: index 5 out of range for length 1; use get_or(index, default) to avoid the fault
// expect-stderr:   at testfaultsourcelocations-16.ms:5 in deep
// expect-stderr:   at testfaultsourcelocations-16.ms:9 in main
