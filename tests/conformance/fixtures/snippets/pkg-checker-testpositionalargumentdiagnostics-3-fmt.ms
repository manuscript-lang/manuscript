# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/positional_arguments_test.go:68 TestPositionalArgumentDiagnostics
fn f(n: Int) Int: n
fn apply(callback: fn(value: Int) Int, input: Int) Int: callback(input)
