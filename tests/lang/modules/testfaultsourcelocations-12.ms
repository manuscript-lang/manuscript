// conform: tags=modules,stdlib-errors,tier-stdlib,try-result
// conform: phase=run
// conform: origin=tests/e2e/fault_locations_test.go:111 TestFaultSourceLocations

fn crash(cause Error) Int {
	return 1 / "".length()
}

export fn main() Int {
	value Int!Error := error(Error("expected failure"))
	return value.get_or_else(crash)
}
// expect-exit: 134
// expect-stderr: division by zero; right must be nonzero, found 0
// expect-stderr:   at testfaultsourcelocations-12.ms:6 in crash
// expect-stderr:   at @std/core.ms:<LINE> in Result.get_or_else
// expect-stderr:   at testfaultsourcelocations-12.ms:11 in main
