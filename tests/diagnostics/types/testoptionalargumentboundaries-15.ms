// conform: tags=diagnostics,formatter,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/optional_test.go:38 TestOptionalArgumentBoundaries
fn f(value Int?) Void => return

fn call() Void => f(other: 4)
// expect-error: MS3004 6:21 unknown argument other; parameters of f: value
