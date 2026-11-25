// conform: tags=faults,modules,stdlib-errors,tier-stdlib,try-result
// conform: phase=run
// conform: origin=tests/e2e/fault_locations_test.go:92 TestFaultSourceLocations

fn deep(value Int!Error) Int {
	return value.get()
}

export fn main() Int {
	return deep(error(Error("expected failure")))
}
// expect-exit: 134
// expect-stderr: called Result.get() on error: Error(details: Map(), kind: none, message: expected failure); check is_ok first, or use get_or(default)
// expect-stderr:   at @std/core.ms:<LINE> in Result.get
// expect-stderr:   at testfaultsourcelocations-9.ms:6 in deep
// expect-stderr:   at testfaultsourcelocations-9.ms:10 in main
