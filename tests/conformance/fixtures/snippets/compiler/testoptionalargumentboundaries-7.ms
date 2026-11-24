// conform: tags=diagnostics,optional,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:30 TestOptionalArgumentBoundaries
fn f(value Int??) Void => return

fn call() Void => f(4)
