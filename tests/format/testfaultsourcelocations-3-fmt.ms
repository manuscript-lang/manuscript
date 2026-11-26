// conform: tags=control-flow,faults,formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/fault_locations_test.go:35 TestFaultSourceLocations

fn checked(n Int) Int!Error {
	if n < 0 {
		return error(Error("negative"))
	}
	return ok(n + 1)
}

fn chain(n Int) Int!Error {
	value := checked(n)?
	return ok(value)
}

export fn main() Int {
	return chain(9223372036854775807).get()
}
// expect-format: rewritten
// expect-formatted:
// expect-formatted: fn checked(n Int) Int! {
// expect-formatted: \tif n < 0 {
// expect-formatted: \t\treturn error(Error("negative"))
// expect-formatted: \t}
// expect-formatted: \treturn ok(n + 1)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn chain(n Int) Int! {
// expect-formatted: \tvalue := checked(n)?
// expect-formatted: \treturn ok(value)
// expect-formatted: }
// expect-formatted:
// expect-formatted: export fn main() Int {
// expect-formatted: \treturn chain(9223372036854775807).get()
// expect-formatted: }
