// conform: tags=diagnostics,optional,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:24 TestOptionalArgumentBoundaries
fn f(value Int?) Void => return

fn call() Void => f("wrong")
// expect-error: MS3001 6:21 expected Int?, found String (in argument 'value' of f)
