// conform: tags=diagnostics,numbers,optional,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:32 TestOptionalArgumentBoundaries
fn f(value Float?) Void => return

fn call(value Int?) Void => f(value)
// expect-error: MS3001 6:31 expected Float?, found Int? (in argument 'value' of f)
