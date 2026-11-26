// conform: tags=aliasing,modules,stdlib-errors,tier-stdlib,try-result
// conform: phase=run
// conform: origin=tests/e2e/fault_locations_test.go:98 TestFaultSourceLocations

export fn main() Int {
	value Int!Error := ok(0)
	extract := value.err
	return extract().text.scalar_length()
}
// expect-exit: 1
// expect-stderr: <DIR>/testfaultsourcelocations-10.ms:8:22: resolution: unknown or ambiguous member text on Error; available: details, kind, message
// expect-stderr:    |
// expect-stderr:  8 |     return extract().text.scalar_length()
// expect-stderr:    |                      ^
// expect-stderr: 1 error; fix them and re-run (ms check --only types <file> --json gives the same diagnostics as structured data)
