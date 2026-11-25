// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/positional_arguments_test.go:19 TestPositionalSignatureHelp
fn subtract(amount Int, deduction Int) Int => amount - deduction

fn run() Int {
	return
}
// expect-error: MS3000 7:5 bare return requires Void or Void!; this function returns Int, so write 'return <value>'
