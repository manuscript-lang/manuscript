// conform: tags=diagnostics,generics,optional,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:33 TestOptionalArgumentBoundaries
fn f[T](second T, first T?) Void => return

fn call() Void => f(first: 4, second: "wrong")
// expect-error: MS3080 6:31 conflicting generic inference; arguments imply different types for one type parameter, so make them the same type or give type arguments explicitly, e.g. f[Int](...)
// expect-error: MS3001 6:39 expected Int, found String (in argument 'second' of f)
