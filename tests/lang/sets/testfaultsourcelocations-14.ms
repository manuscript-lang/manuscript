// conform: tags=formatter,sets,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:124 TestFaultSourceLocations
fn crash(value Int) Int {
	return 1 / value
}

export fn main() Int {
	var value = Set[Int]()
	value.add(0)
	return value.map(crash).length()
}
// expect-exit: 134
// expect-stderr: division by zero; right must be nonzero, found 0
// expect-stderr:   at testfaultsourcelocations-14.ms:5 in crash
// expect-stderr:   at @std/collections/collections.ms:<LINE> in Set.map
// expect-stderr:   at testfaultsourcelocations-14.ms:11 in main
