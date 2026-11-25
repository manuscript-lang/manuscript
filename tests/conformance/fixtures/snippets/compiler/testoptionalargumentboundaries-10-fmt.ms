// conform: tags=formatter,generics,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/optional_test.go:33 TestOptionalArgumentBoundaries
fn f[T](second T, first T?) Void => return

fn call() Void => f(first: 4, second: "wrong")
