// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/lsp/positional_arguments_test.go:19 TestPositionalSignatureHelp
fn subtract(amount Int, deduction Int) Int => amount - deduction

fn run() Int {
	return
}
// expect-format: rewritten
// expect-formatted: fn subtract(amount, deduction Int) Int => amount - deduction
// expect-formatted:
// expect-formatted: fn run() Int {
// expect-formatted: \treturn
// expect-formatted: }
