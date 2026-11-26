// conform: tags=diagnostics,formatter,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/optional_test.go:26 TestOptionalArgumentBoundaries
fn f(value Int?) Void => return

fn call() Void => f()
// expect-exit: 0
