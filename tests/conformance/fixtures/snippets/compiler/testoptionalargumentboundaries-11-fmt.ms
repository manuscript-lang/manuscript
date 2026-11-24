// conform: tags=formatter,generics,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/optional_test.go:34 TestOptionalArgumentBoundaries
fn f[T](value T?) Void => return

fn call() Void => f()
