// conform: tags=control-flow,formatter,interfaces,records,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:47 TestFaultSourceLocations
interface Counter {
	var fn bump(by Int) Int
}

type Cell {
	total Int
}

fn var Cell.bump(by Int) Int {
	self.total += by
	return self.total
}

fn probe(value Int) Int {
	var cell = Cell(0)
	cell.bump(value)
	cell.bump(1)
	return cell.total
}

export fn main() Int {
	return probe(9223372036854775807)
}
// expect-exit: 134
// expect-stderr: Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt
// expect-stderr:   at testfaultsourcelocations-4.ms:13 in Cell.bump
// expect-stderr:   at testfaultsourcelocations-4.ms:20 in probe
// expect-stderr:   at testfaultsourcelocations-4.ms:25 in main
