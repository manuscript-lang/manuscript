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
