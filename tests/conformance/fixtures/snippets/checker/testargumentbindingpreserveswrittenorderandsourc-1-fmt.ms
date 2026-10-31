# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/positional_arguments_test.go:26 TestArgumentBindingPreservesWrittenOrderAndSource
fn f(first: Int = 1, second: Int = 2, third: Int = 3) Int: first

fn run(first: Int, second: Int, third: Int) Int: ...
