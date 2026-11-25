// conform: tags=modules,optional,stdlib-errors,tier-stdlib
// conform: phase=run
// conform: origin=tests/e2e/conversions_queries_test.go:38 TestLazyConversionFaultLocation

fn crash() Error {
	return Error((1 / "".length()).to_string())
}

fn main() Void {
	value Int? := null
	_result := ok_or(value, crash())
}
// expect-exit: 134
// expect-stderr: division by zero; right must be nonzero, found 0
// expect-stderr:   at testlazyconversionfaultlocation-1.ms:6 in crash
// expect-stderr:   at testlazyconversionfaultlocation-1.ms:11 in main
