# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/positional_arguments_test.go:68 TestPositionalArgumentDiagnostics
fn f(n: Int) Int: n

fn apply(callback: fn(Int) Int, input: Int) Int: callback(input)
