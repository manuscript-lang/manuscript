// conform: tags=formatter,numbers,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/optional_test.go:25 TestOptionalArgumentBoundaries
fn f(value Float?) Void => return

fn call() Void => f(4)
