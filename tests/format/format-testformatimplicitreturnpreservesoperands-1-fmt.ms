// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/format/format_test.go:44 TestFormatImplicitReturnPreservesOperands
fn sum(first_value Int, second_value Int, third_value Int, fourth_value Int) Int => (
	first_value
	+ second_value
	+ third_value
	+ fourth_value
)
// expect-format: rewritten
// expect-formatted: fn sum(first_value, second_value, third_value, fourth_value Int) Int => (
// expect-formatted: \tfirst_value
// expect-formatted: \t+ second_value
// expect-formatted: \t+ third_value
// expect-formatted: \t+ fourth_value
// expect-formatted: )
