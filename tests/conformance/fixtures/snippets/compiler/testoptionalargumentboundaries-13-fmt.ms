// conform: tags=formatter,lists,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/optional_test.go:36 TestOptionalArgumentBoundaries
fn f(values List[Int?]) Void => return

fn call() Void => f([4])
