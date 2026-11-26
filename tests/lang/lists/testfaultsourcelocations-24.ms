// conform: tags=formatter,lists,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:189 TestFaultSourceLocations
fn empty() List[Int] {
	return []
}

export fn main() Int {
	[value] := empty()
	return value
}
// expect-exit: 134
// expect-stderr: destructuring length mismatch; the pattern binds 1 names but the list has 0 elements
// expect-stderr:   at testfaultsourcelocations-24.ms:9 in main
