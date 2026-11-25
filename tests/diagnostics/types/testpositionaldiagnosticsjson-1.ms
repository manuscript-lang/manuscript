// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=tests/e2e/positional_arguments_test.go:46 TestPositionalDiagnosticsJSON
fn f(first Int, second Int) Int => first

export fn main() Int {
	return
}
// expect-error: MS3000 7:5 bare return requires Void or Void!; this function returns Int, so write 'return <value>'
