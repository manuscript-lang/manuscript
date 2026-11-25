// conform: tags=diagnostics,formatter,lists,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/optional_test.go:36 TestOptionalArgumentBoundaries
fn f(values List[Int?]) Void => return

fn call() Void => f([4])
// expect-exit: 0
