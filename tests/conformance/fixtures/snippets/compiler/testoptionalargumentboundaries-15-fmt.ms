// conform: tags=formatter,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/optional_test.go:38 TestOptionalArgumentBoundaries
fn f(value Int?) Void => return

fn call() Void => f(other: 4)
