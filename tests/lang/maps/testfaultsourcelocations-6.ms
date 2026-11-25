// conform: tags=formatter,maps,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:74 TestFaultSourceLocations
fn crash() Int {
	return 1 / "".length()
}

export fn main() Int {
	var values = Map[Int, Int]()
	values.add(crash(), 1)
	return values.length()
}
// expect-exit: 134
// expect-stderr: division by zero; right must be nonzero, found 0
// expect-stderr:   at testfaultsourcelocations-6.ms:5 in crash
// expect-stderr:   at testfaultsourcelocations-6.ms:10 in main
