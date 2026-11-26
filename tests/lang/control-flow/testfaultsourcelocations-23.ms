// conform: tags=control-flow,formatter,interfaces,records,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:177 TestFaultSourceLocations
interface Crash {
	fn run() Int
}

type Item {
	value Int
}

fn Item.run() Int {
	return 1 / self.value
}

export fn main() Int {
	item := Item(0)
	run := item.run
	return run()
}
// expect-exit: 134
// expect-stderr: division by zero; right must be nonzero, found 0
// expect-stderr:   at testfaultsourcelocations-23.ms:13 in Item.run
// expect-stderr:   at testfaultsourcelocations-23.ms:19 in main
