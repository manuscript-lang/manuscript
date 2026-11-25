// conform: tags=diagnostics
// conform: phase=check
fn f[T](second T, first T?) Void => return

fn call() Void => f(first: 4, second: "wrong")
// expect-error: MS3080 5:31 conflicting generic inference; arguments imply different types for one type parameter, so make them the same type or give type arguments explicitly, e.g. f[Int](...)
// expect-error: MS3001 5:39 expected Int, found String (in argument 'second' of f)
