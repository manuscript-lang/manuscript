# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/positional_arguments_test.go:46 TestPositionalDiagnosticsJSON
fn f(first: Int, second: Int) Int: first
export fn main() Int:
    return 
