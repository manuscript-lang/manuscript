// conform: tags=formatter,parser,testing,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/e2e_test.go:70 TestRuntimeFaults
fn divide(value Int, divisor Int) Int {
	return value / divisor
}

test "fault" {
	_impossible := divide(value: 3, divisor: 0)
}
// expect-format: rewritten
// expect-formatted: fn divide(value, divisor Int) Int {
// expect-formatted: \treturn value / divisor
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "fault" {
// expect-formatted: \t_impossible := divide(value: 3, divisor: 0)
// expect-formatted: }
