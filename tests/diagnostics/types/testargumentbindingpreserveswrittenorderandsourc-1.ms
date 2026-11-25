// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/positional_arguments_test.go:26 TestArgumentBindingPreservesWrittenOrderAndSource
fn f(first Int = 1, second Int = 2, third Int = 3) Int => first

fn run(first Int, second Int, third Int) Int { ... }
// expect-error: MS3000 6:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
