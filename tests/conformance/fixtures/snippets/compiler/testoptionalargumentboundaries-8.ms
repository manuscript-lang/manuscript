// conform: tags=diagnostics,optional,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:31 TestOptionalArgumentBoundaries
fn f(value Int) Void => return

fn call() Void => f(4)
// expect-exit: 0
