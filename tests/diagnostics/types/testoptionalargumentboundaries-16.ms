// conform: tags=diagnostics,formatter,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/optional_test.go:39 TestOptionalArgumentBoundaries
fn f(value Int?) Void => return

fn call() Void => f(4, value: 5)
// expect-error: MS3002 6:24 duplicate argument value; pass each argument once
