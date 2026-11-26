// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/lsp/positional_arguments_test.go:27 TestPositionalIdentifierRenameDoesNotAddLabels
fn subtract(amount Int, deduction Int) Int => amount - deduction

fn run() Int {
	number := 10
	return subtract(number, 3)
}
// expect-format: rewritten
// expect-formatted: fn subtract(amount, deduction Int) Int => amount - deduction
// expect-formatted:
// expect-formatted: fn run() Int {
// expect-formatted: \tnumber := 10
// expect-formatted: \treturn subtract(number, 3)
// expect-formatted: }
