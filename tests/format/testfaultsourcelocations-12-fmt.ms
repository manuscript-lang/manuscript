// conform: tags=formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/fault_locations_test.go:111 TestFaultSourceLocations

fn crash(cause Error) Int {
	return 1 / "".length()
}

export fn main() Int {
	value Int!Error := error(Error("expected failure"))
	return value.get_or_else(crash)
}
// expect-format: rewritten
// expect-formatted:
// expect-formatted: fn crash(cause Error) Int {
// expect-formatted: \treturn 1 / "".length()
// expect-formatted: }
// expect-formatted:
// expect-formatted: export fn main() Int {
// expect-formatted: \tvalue Int! := error(Error("expected failure"))
// expect-formatted: \treturn value.get_or_else(crash)
// expect-formatted: }
