// conform: tags=faults,formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/fault_locations_test.go:92 TestFaultSourceLocations

fn deep(value Int!Error) Int {
	return value.get()
}

export fn main() Int {
	return deep(error(Error("expected failure")))
}
// expect-format: rewritten
// expect-formatted:
// expect-formatted: fn deep(value Int!) Int {
// expect-formatted: \treturn value.get()
// expect-formatted: }
// expect-formatted:
// expect-formatted: export fn main() Int {
// expect-formatted: \treturn deep(error(Error("expected failure")))
// expect-formatted: }
